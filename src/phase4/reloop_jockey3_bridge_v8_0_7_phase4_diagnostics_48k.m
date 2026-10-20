#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMIDI/CoreMIDI.h>
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import <math.h>
#import <unistd.h>
#import <signal.h>
#import <time.h>
#import <limits.h>
#import <pthread.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/thread_policy.h>
#import <sys/stat.h>
#import <stdio.h>
#import <errno.h>

#define VID 0x200c
#define PID 0x1019

#define PLOYTEC_PKT_SIZE 512
#define BATCH_PKTS 8
#define BATCH_SIZE (PLOYTEC_PKT_SIZE * BATCH_PKTS)

#define MIDI_OUT_OFFSET 480
#define SYNC_OFFSET 481
#define MIDI_IDLE 0xFD
#define SYNC_VALUE 0xFF


#define SAMPLE_RATE 48000
#define PLOYTEC_AUDIO_FRAMES_PER_PACKET 10

#define MIDI_OUT_RING_CAPACITY 16384u
#define MIDI_OUT_RATE_BYTES_PER_SEC 2500u
#define MIDI_PACKET_RATE (SAMPLE_RATE / PLOYTEC_AUDIO_FRAMES_PER_PACKET)

typedef struct {
    uint8_t bytes[MIDI_OUT_RING_CAPACITY];
    atomic_uint_fast64_t writeIndex;
    atomic_uint_fast64_t readIndex;
    atomic_ulong coreMidiPacketsReceived;
    atomic_ulong bytesReceived;
    atomic_ulong bytesDropped;
    atomic_ulong wireBytesSent;
    atomic_bool accepting;
} MidiOutRing;

typedef struct {
    int expectedData;
    int dataCount;
    uint8_t runningStatus;
    uint8_t queuedByte;
    bool hasQueuedByte;
} MidiRunningStatus;

typedef struct {
    MIDIClientRef client;
    MIDIEndpointRef source;
    MIDIEndpointRef destination;
    MidiOutRing *outRing;

    /*
     * v8.0.7 keeps the v8.0.4 MIDI OUT filter state unchanged.
     *
     * Traktor sends two hidden "actual Tempo Master" outputs on Channel 16:
     *   Ch16.Note.C0  = Deck A master state
     *   Ch16.Note.C#0 = Deck B master state
     *
     * Beat Phase for the physical trash LEDs remains on:
     *   Ch01.Note.A-1 = Deck A trash LED
     *   Ch02.Note.A-1 = Deck B trash LED
     *
     * Play/Pause LED outputs are:
     *   Ch01.Note.D1 = Deck A Play/Pause LED
     *   Ch02.Note.D1 = Deck B Play/Pause LED
     *
     * The filter forwards Beat Phase only for the deck Traktor reports as
     * Tempo Master and mirrors that same phase value to the master deck's
     * Play/Pause LED. While a deck is master, its ordinary steady Play/Pause
     * LED output is cached but suppressed. When it stops being master, the
     * cached ordinary Play/Pause LED state is restored immediately. All other
     * Traktor MIDI OUT messages pass through unchanged.
     */
    uint8_t midiOutFilterRunningStatus;
    uint8_t midiOutFilterMessage[3];
    uint8_t midiOutFilterLength;
    uint8_t midiOutFilterExpectedLength;
    atomic_bool deckAMaster;
    atomic_bool deckBMaster;
    uint8_t deckAPlayLedValue;
    uint8_t deckBPlayLedValue;
    atomic_ulong masterStateMessagesFiltered;
    atomic_ulong beatPhaseMessagesForwarded;
    atomic_ulong beatPhaseMessagesBlocked;
    atomic_ulong playLedMessagesMirrored;
    atomic_ulong playLedMessagesSuppressed;
    atomic_ulong playLedStateRestores;
    pthread_mutex_t midiOutFilterMutex;
    bool midiOutFilterMutexReady;

    /*
     * EP 0x83 is a raw byte stream. One MIDI message is frequently split over
     * several USB completions (for example B0, then 35, then 41). Keep parser
     * state across completions and publish only complete MIDI messages.
     */
    uint8_t midiInRunningStatus;
    uint8_t midiInMessage[3];
    uint8_t midiInLength;
    uint8_t midiInExpectedLength;

    atomic_ulong midiInBatchesForwarded;
    atomic_ulong midiInMessagesForwarded;
    atomic_ulong midiInBytesForwarded;
    atomic_ulong midiInForwardErrors;
} CoreMidiBridge;

static void midiOutRingInit(MidiOutRing *ring)
{
    memset(ring, 0, sizeof(*ring));
    atomic_init(&ring->writeIndex, 0);
    atomic_init(&ring->readIndex, 0);
    atomic_init(&ring->coreMidiPacketsReceived, 0);
    atomic_init(&ring->bytesReceived, 0);
    atomic_init(&ring->bytesDropped, 0);
    atomic_init(&ring->wireBytesSent, 0);
    atomic_init(&ring->accepting, false);
}

static uint64_t midiOutRingDepth(const MidiOutRing *ring)
{
    uint64_t wr = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    uint64_t rd = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    return wr >= rd ? wr - rd : 0;
}

/*
 * Traktor is the producer for the virtual CoreMIDI destination; the playback
 * pthread is the consumer. Publish writeIndex only after storing the byte so
 * the real-time playback side remains lock-free.
 */
static void midiOutRingPushByte(MidiOutRing *ring, uint8_t byte)
{
    if (!atomic_load_explicit(&ring->accepting, memory_order_acquire))
        return;

    uint64_t wr = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&ring->readIndex, memory_order_acquire);

    atomic_fetch_add_explicit(&ring->bytesReceived, 1, memory_order_relaxed);

    if (wr - rd >= MIDI_OUT_RING_CAPACITY) {
        atomic_fetch_add_explicit(&ring->bytesDropped, 1, memory_order_relaxed);
        return;
    }

    ring->bytes[wr % MIDI_OUT_RING_CAPACITY] = byte;
    atomic_store_explicit(&ring->writeIndex, wr + 1, memory_order_release);
}

static bool midiOutRingPopByte(MidiOutRing *ring, uint8_t *byte)
{
    uint64_t rd = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    uint64_t wr = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);

    if (rd == wr)
        return false;

    *byte = ring->bytes[rd % MIDI_OUT_RING_CAPACITY];
    atomic_store_explicit(&ring->readIndex, rd + 1, memory_order_release);
    return true;
}

/* Expand MIDI 1.0 Running Status for the Ploytec firmware. */
static uint8_t midiExpandRunningStatus(MidiRunningStatus *state, uint8_t b)
{
    if (b >= 0x80) {
        if (b < 0xF0) {
            state->runningStatus = b;
            state->expectedData =
                ((b & 0xF0) == 0xC0 || (b & 0xF0) == 0xD0) ? 1 : 2;
        } else if (b < 0xF8) {
            state->runningStatus = 0;
            state->expectedData = 0;
        } else {
            return b;
        }

        state->dataCount = state->expectedData;
        return b;
    }

    if (state->dataCount > 0) {
        state->dataCount--;
        return b;
    }

    if (state->runningStatus >= 0x80) {
        uint8_t status = state->runningStatus;
        state->queuedByte = b;
        state->hasQueuedByte = true;
        state->dataCount = state->expectedData - 1;
        return status;
    }

    return b;
}

static uint8_t midiNextWireByte(MidiOutRing *ring,
                                MidiRunningStatus *state,
                                uint32_t *rateAccumulator)
{
    /*
     * At 48 kHz there are 4800 packet/MIDI slots per second. Limit actual MIDI
     * bytes to about 2500 bytes/s, matching the current Linux Jockey 3 driver.
     */
    *rateAccumulator += MIDI_OUT_RATE_BYTES_PER_SEC;
    if (*rateAccumulator < MIDI_PACKET_RATE)
        return MIDI_IDLE;

    *rateAccumulator -= MIDI_PACKET_RATE;

    uint8_t out = MIDI_IDLE;

    if (state->hasQueuedByte) {
        state->hasQueuedByte = false;
        out = state->queuedByte;
    } else {
        uint8_t raw = 0;
        if (!midiOutRingPopByte(ring, &raw))
            return MIDI_IDLE;
        out = midiExpandRunningStatus(state, raw);
    }

    atomic_fetch_add_explicit(&ring->wireBytesSent, 1, memory_order_relaxed);
    return out;
}

static void injectMidiOutIntoPlaybackBatch(uint8_t *batch,
                                           MidiOutRing *ring,
                                           MidiRunningStatus *state,
                                           uint32_t *rateAccumulator)
{
    for (int p = 0; p < BATCH_PKTS; p++) {
        uint8_t *packet = batch + p * PLOYTEC_PKT_SIZE;
        packet[MIDI_OUT_OFFSET] =
            midiNextWireByte(ring, state, rateAccumulator);
    }
}

static uint8_t midiChannelMessageLength(uint8_t status);

static void midiOutRingPushMessage(MidiOutRing *ring,
                                   const uint8_t *message,
                                   uint8_t length)
{
    if (!ring || !message || length == 0)
        return;

    for (uint8_t i = 0; i < length; i++)
        midiOutRingPushByte(ring, message[i]);
}

static void coreMidiForceTrashLedOff(CoreMidiBridge *bridge, uint8_t deck)
{
    if (!bridge || !bridge->outRing)
        return;

    const uint8_t message[3] = {
        (uint8_t)(deck == 0 ? 0x90 : 0x91),
        9, /* A-1 */
        0
    };
    midiOutRingPushMessage(bridge->outRing, message, 3);
}

static void coreMidiSendPlayLedValue(CoreMidiBridge *bridge,
                                     uint8_t deck,
                                     uint8_t value)
{
    if (!bridge || !bridge->outRing)
        return;

    const uint8_t message[3] = {
        (uint8_t)(deck == 0 ? 0x90 : 0x91),
        26, /* D1 */
        value
    };
    midiOutRingPushMessage(bridge->outRing, message, 3);
}

static void coreMidiRestorePlayLed(CoreMidiBridge *bridge, uint8_t deck)
{
    if (!bridge)
        return;

    uint8_t value = deck == 0
        ? bridge->deckAPlayLedValue
        : bridge->deckBPlayLedValue;

    coreMidiSendPlayLedValue(bridge, deck, value);
    atomic_fetch_add_explicit(&bridge->playLedStateRestores,
                              1,
                              memory_order_relaxed);
}

static void coreMidiHandleOutputMessage(CoreMidiBridge *bridge,
                                        const uint8_t *message,
                                        uint8_t length)
{
    if (!bridge || !bridge->outRing || !message || length == 0)
        return;

    if (length == 3) {
        uint8_t status = message[0];
        uint8_t type = status & 0xF0;
        uint8_t channel = status & 0x0F;
        uint8_t note = message[1];
        uint8_t value = message[2];

        /*
         * Hidden actual Tempo Master state.
         *
         * Channel 16, C0  -> Deck A
         * Channel 16, C#0 -> Deck B
         *
         * These messages are consumed internally and never reach the Reloop.
         */
        if ((type == 0x90 || type == 0x80) &&
            channel == 15 &&
            (note == 12 || note == 13)) {
            bool on = (type == 0x90 && value > 0);

            if (note == 12) {
                bool wasA = atomic_exchange_explicit(&bridge->deckAMaster,
                                                     on,
                                                     memory_order_acq_rel);
                if (on) {
                    bool wasB = atomic_exchange_explicit(&bridge->deckBMaster,
                                                         false,
                                                         memory_order_acq_rel);
                    coreMidiForceTrashLedOff(bridge, 1);
                    if (wasB)
                        coreMidiRestorePlayLed(bridge, 1);
                    if (!wasA)
                        coreMidiSendPlayLedValue(bridge, 0, 0);
                } else if (wasA) {
                    coreMidiForceTrashLedOff(bridge, 0);
                    coreMidiRestorePlayLed(bridge, 0);
                }
            } else {
                bool wasB = atomic_exchange_explicit(&bridge->deckBMaster,
                                                     on,
                                                     memory_order_acq_rel);
                if (on) {
                    bool wasA = atomic_exchange_explicit(&bridge->deckAMaster,
                                                         false,
                                                         memory_order_acq_rel);
                    coreMidiForceTrashLedOff(bridge, 0);
                    if (wasA)
                        coreMidiRestorePlayLed(bridge, 0);
                    if (!wasB)
                        coreMidiSendPlayLedValue(bridge, 1, 0);
                } else if (wasB) {
                    coreMidiForceTrashLedOff(bridge, 1);
                    coreMidiRestorePlayLed(bridge, 1);
                }
            }

            atomic_fetch_add_explicit(&bridge->masterStateMessagesFiltered,
                                      1,
                                      memory_order_relaxed);
            return;
        }

        /*
         * Ordinary Play/Pause LED state. Preserve it for the non-master
         * behavior, but do not let it fight the Beat Phase mirror while that
         * deck is the actual Tempo Master.
         */
        if ((type == 0x90 || type == 0x80) &&
            note == 26 &&
            (channel == 0 || channel == 1)) {
            uint8_t ledValue = (type == 0x90) ? value : 0;
            if (channel == 0)
                bridge->deckAPlayLedValue = ledValue;
            else
                bridge->deckBPlayLedValue = ledValue;

            bool isMaster =
                channel == 0
                    ? atomic_load_explicit(&bridge->deckAMaster,
                                           memory_order_acquire)
                    : atomic_load_explicit(&bridge->deckBMaster,
                                           memory_order_acquire);

            if (isMaster) {
                atomic_fetch_add_explicit(&bridge->playLedMessagesSuppressed,
                                          1,
                                          memory_order_relaxed);
            } else {
                midiOutRingPushMessage(bridge->outRing, message, length);
            }
            return;
        }

        /*
         * Beat Phase directed to the two physical trash LEDs.
         * Forward only the actual Tempo Master's trash LED and mirror the
         * same phase value to that deck's Play/Pause LED.
         */
        if ((type == 0x90 || type == 0x80) &&
            note == 9 &&
            (channel == 0 || channel == 1)) {
            bool isMaster =
                channel == 0
                    ? atomic_load_explicit(&bridge->deckAMaster,
                                           memory_order_acquire)
                    : atomic_load_explicit(&bridge->deckBMaster,
                                           memory_order_acquire);

            if (isMaster) {
                midiOutRingPushMessage(bridge->outRing, message, length);

                uint8_t playMessage[3] = {
                    status,
                    26, /* D1 */
                    value
                };
                midiOutRingPushMessage(bridge->outRing, playMessage, 3);

                atomic_fetch_add_explicit(&bridge->beatPhaseMessagesForwarded,
                                          1,
                                          memory_order_relaxed);
                atomic_fetch_add_explicit(&bridge->playLedMessagesMirrored,
                                          1,
                                          memory_order_relaxed);
            } else {
                atomic_fetch_add_explicit(&bridge->beatPhaseMessagesBlocked,
                                          1,
                                          memory_order_relaxed);
            }
            return;
        }
    }

    /* Every unrelated Traktor MIDI OUT message passes through unchanged. */
    midiOutRingPushMessage(bridge->outRing, message, length);
}

static void coreMidiConsumeOutputBytes(CoreMidiBridge *bridge,
                                       const uint8_t *bytes,
                                       size_t count)
{
    if (!bridge || !bridge->outRing || !bytes || count == 0)
        return;

    for (size_t i = 0; i < count; i++) {
        uint8_t b = bytes[i];

        /* MIDI real-time bytes are single-byte messages and may appear anywhere. */
        if (b >= 0xF8) {
            midiOutRingPushByte(bridge->outRing, b);
            continue;
        }

        /*
         * System common / SysEx is unrelated to the LED gate. Pass it through
         * raw and clear channel running-status assembly state.
         */
        if (b >= 0xF0) {
            bridge->midiOutFilterRunningStatus = 0;
            bridge->midiOutFilterLength = 0;
            bridge->midiOutFilterExpectedLength = 0;
            midiOutRingPushByte(bridge->outRing, b);
            continue;
        }

        if (b & 0x80) {
            uint8_t expected = midiChannelMessageLength(b);
            if (expected == 0) {
                midiOutRingPushByte(bridge->outRing, b);
                continue;
            }

            bridge->midiOutFilterRunningStatus = b;
            bridge->midiOutFilterMessage[0] = b;
            bridge->midiOutFilterLength = 1;
            bridge->midiOutFilterExpectedLength = expected;
            continue;
        }

        /*
         * Data byte. If CoreMIDI uses running status, reconstruct the explicit
         * status byte before filtering. The downstream Ploytec path already
         * expands running status, so this does not change wire semantics.
         */
        if (bridge->midiOutFilterLength == 0) {
            uint8_t status = bridge->midiOutFilterRunningStatus;
            uint8_t expected = midiChannelMessageLength(status);

            if (expected == 0) {
                midiOutRingPushByte(bridge->outRing, b);
                continue;
            }

            bridge->midiOutFilterMessage[0] = status;
            bridge->midiOutFilterLength = 1;
            bridge->midiOutFilterExpectedLength = expected;
        }

        if (bridge->midiOutFilterLength <
            sizeof(bridge->midiOutFilterMessage)) {
            bridge->midiOutFilterMessage[bridge->midiOutFilterLength++] = b;
        } else {
            bridge->midiOutFilterLength = 0;
            bridge->midiOutFilterExpectedLength = 0;
            continue;
        }

        if (bridge->midiOutFilterExpectedLength != 0 &&
            bridge->midiOutFilterLength ==
                bridge->midiOutFilterExpectedLength) {
            coreMidiHandleOutputMessage(bridge,
                                        bridge->midiOutFilterMessage,
                                        bridge->midiOutFilterLength);
            bridge->midiOutFilterLength = 0;
            bridge->midiOutFilterExpectedLength = 0;
        }
    }
}

static void coreMidiDestinationReadProc(const MIDIPacketList *packetList,
                                        void *readProcRefCon,
                                        void *srcConnRefCon)
{
    (void)srcConnRefCon;

    CoreMidiBridge *bridge = (CoreMidiBridge *)readProcRefCon;
    if (!bridge || !bridge->outRing || !packetList)
        return;

    MIDIPacket *packet = (MIDIPacket *)&packetList->packet[0];

    for (UInt32 i = 0; i < packetList->numPackets; i++) {
        atomic_fetch_add_explicit(&bridge->outRing->coreMidiPacketsReceived,
                                  1,
                                  memory_order_relaxed);

        if (bridge->midiOutFilterMutexReady)
            pthread_mutex_lock(&bridge->midiOutFilterMutex);

        coreMidiConsumeOutputBytes(bridge,
                                   packet->data,
                                   packet->length);

        if (bridge->midiOutFilterMutexReady)
            pthread_mutex_unlock(&bridge->midiOutFilterMutex);

        packet = MIDIPacketNext(packet);
    }
}

static OSStatus setupCoreMidiBridge(CoreMidiBridge *bridge, MidiOutRing *outRing)
{
    memset(bridge, 0, sizeof(*bridge));
    bridge->outRing = outRing;
    bridge->midiInRunningStatus = 0;
    bridge->midiInLength = 0;
    bridge->midiInExpectedLength = 0;
    bridge->midiOutFilterRunningStatus = 0;
    bridge->midiOutFilterLength = 0;
    bridge->midiOutFilterExpectedLength = 0;
    atomic_init(&bridge->deckAMaster, false);
    atomic_init(&bridge->deckBMaster, false);
    bridge->deckAPlayLedValue = 0;
    bridge->deckBPlayLedValue = 0;
    atomic_init(&bridge->masterStateMessagesFiltered, 0);
    atomic_init(&bridge->beatPhaseMessagesForwarded, 0);
    atomic_init(&bridge->beatPhaseMessagesBlocked, 0);
    atomic_init(&bridge->playLedMessagesMirrored, 0);
    atomic_init(&bridge->playLedMessagesSuppressed, 0);
    atomic_init(&bridge->playLedStateRestores, 0);
    bridge->midiOutFilterMutexReady = false;
    if (pthread_mutex_init(&bridge->midiOutFilterMutex, NULL) != 0)
        return (OSStatus)-1;
    bridge->midiOutFilterMutexReady = true;
    atomic_init(&bridge->midiInBatchesForwarded, 0);
    atomic_init(&bridge->midiInMessagesForwarded, 0);
    atomic_init(&bridge->midiInBytesForwarded, 0);
    atomic_init(&bridge->midiInForwardErrors, 0);

    OSStatus status =
        MIDIClientCreate(CFSTR("Reloop Jockey 3 ME Bridge Client"),
                         NULL,
                         NULL,
                         &bridge->client);
    if (status != noErr) {
        if (bridge->midiOutFilterMutexReady) {
            pthread_mutex_destroy(&bridge->midiOutFilterMutex);
            bridge->midiOutFilterMutexReady = false;
        }
        return status;
    }

    status =
        MIDISourceCreate(bridge->client,
                         CFSTR("Reloop Jockey 3 ME (Bridge)"),
                         &bridge->source);
    if (status != noErr) {
        MIDIClientDispose(bridge->client);
        bridge->client = 0;
        if (bridge->midiOutFilterMutexReady) {
            pthread_mutex_destroy(&bridge->midiOutFilterMutex);
            bridge->midiOutFilterMutexReady = false;
        }
        return status;
    }

    status =
        MIDIDestinationCreate(bridge->client,
                              CFSTR("Reloop Jockey 3 ME (Bridge)"),
                              coreMidiDestinationReadProc,
                              bridge,
                              &bridge->destination);
    if (status != noErr) {
        MIDIEndpointDispose(bridge->source);
        MIDIClientDispose(bridge->client);
        bridge->source = 0;
        bridge->client = 0;
        if (bridge->midiOutFilterMutexReady) {
            pthread_mutex_destroy(&bridge->midiOutFilterMutex);
            bridge->midiOutFilterMutexReady = false;
        }
        return status;
    }

    atomic_store_explicit(&outRing->accepting, true, memory_order_release);
    return noErr;
}

static void disposeCoreMidiBridge(CoreMidiBridge *bridge)
{
    if (!bridge)
        return;

    if (bridge->outRing)
        atomic_store_explicit(&bridge->outRing->accepting,
                              false,
                              memory_order_release);

    if (bridge->destination)
        MIDIEndpointDispose(bridge->destination);
    if (bridge->source)
        MIDIEndpointDispose(bridge->source);
    if (bridge->client)
        MIDIClientDispose(bridge->client);

    bridge->destination = 0;
    bridge->source = 0;
    bridge->client = 0;

    if (bridge->midiOutFilterMutexReady) {
        pthread_mutex_destroy(&bridge->midiOutFilterMutex);
        bridge->midiOutFilterMutexReady = false;
    }
}

static void coreMidiForwardInputBytes(CoreMidiBridge *bridge,
                                      const uint8_t *bytes,
                                      size_t count)
{
    if (!bridge || !bridge->source || !bytes || count == 0)
        return;

    if (count > PLOYTEC_PKT_SIZE)
        count = PLOYTEC_PKT_SIZE;

    uint8_t storage[sizeof(MIDIPacketList) + PLOYTEC_PKT_SIZE + 64];
    MIDIPacketList *packetList = (MIDIPacketList *)storage;
    MIDIPacket *packet = MIDIPacketListInit(packetList);

    packet =
        MIDIPacketListAdd(packetList,
                          sizeof(storage),
                          packet,
                          0,
                          (UInt16)count,
                          bytes);

    if (!packet) {
        atomic_fetch_add_explicit(&bridge->midiInForwardErrors,
                                  1,
                                  memory_order_relaxed);
        return;
    }

    OSStatus status = MIDIReceived(bridge->source, packetList);
    if (status == noErr) {
        atomic_fetch_add_explicit(&bridge->midiInBatchesForwarded,
                                  1,
                                  memory_order_relaxed);
        atomic_fetch_add_explicit(&bridge->midiInBytesForwarded,
                                  (unsigned long)count,
                                  memory_order_relaxed);
    } else {
        atomic_fetch_add_explicit(&bridge->midiInForwardErrors,
                                  1,
                                  memory_order_relaxed);
    }
}

static uint8_t midiChannelMessageLength(uint8_t status)
{
    if (status < 0x80 || status >= 0xF0)
        return 0;

    uint8_t type = status & 0xF0;
    return (type == 0xC0 || type == 0xD0) ? 2 : 3;
}

/*
 * Consume the useful bytes extracted from EP 0x83.
 *
 * The controller's USB transfers are NOT MIDI-message framed. A normal
 * three-byte message can arrive as:
 *
 *     transfer 1: B0
 *     transfer 2: 35
 *     transfer 3: 41
 *
 * v8.0.1 incorrectly handed each transfer fragment directly to CoreMIDI.
 * v8.0.2 carries assembly state across USB completions and calls MIDIReceived()
 * only for complete channel-voice messages. Running status is accepted too.
 *
 * Bytes >= F0 are protocol/system/filler for our controller path and are
 * ignored without destroying a partially assembled channel message.
 */
static void coreMidiConsumeInputBytes(CoreMidiBridge *bridge,
                                      const uint8_t *bytes,
                                      size_t count)
{
    if (!bridge || !bytes || count == 0)
        return;

    for (size_t i = 0; i < count; i++) {
        uint8_t b = bytes[i];

        if (b >= 0xF0) {
            /* Ignore Ploytec/system/filler bytes for the Traktor control path. */
            continue;
        }

        if (b & 0x80) {
            uint8_t expected = midiChannelMessageLength(b);
            if (expected == 0)
                continue;

            bridge->midiInRunningStatus = b;
            bridge->midiInMessage[0] = b;
            bridge->midiInLength = 1;
            bridge->midiInExpectedLength = expected;
            continue;
        }

        /* Data byte. If needed, start a new message from running status. */
        if (bridge->midiInLength == 0) {
            uint8_t status = bridge->midiInRunningStatus;
            uint8_t expected = midiChannelMessageLength(status);
            if (expected == 0)
                continue;

            bridge->midiInMessage[0] = status;
            bridge->midiInLength = 1;
            bridge->midiInExpectedLength = expected;
        }

        if (bridge->midiInLength < sizeof(bridge->midiInMessage))
            bridge->midiInMessage[bridge->midiInLength++] = b;
        else {
            /* Defensive resync; valid channel messages never exceed 3 bytes. */
            bridge->midiInLength = 0;
            bridge->midiInExpectedLength = 0;
            continue;
        }

        if (bridge->midiInExpectedLength != 0 &&
            bridge->midiInLength == bridge->midiInExpectedLength) {
            coreMidiForwardInputBytes(bridge,
                                      bridge->midiInMessage,
                                      bridge->midiInLength);
            atomic_fetch_add_explicit(&bridge->midiInMessagesForwarded,
                                      1,
                                      memory_order_relaxed);

            /*
             * Preserve running status but begin the next message empty.
             * If the controller sends another explicit status, it replaces it.
             */
            bridge->midiInLength = 0;
            bridge->midiInExpectedLength = 0;
        }
    }
}



#define PCM_CHANNELS 4
#define PCM_FRAME_BYTES 12
#define PLOYTEC_AUDIO_FRAME_BYTES 48

/*
 * Direct playback test level: approximately -30 dBFS.
 * This is intentionally quiet; use the controller's physical output knobs
 * to raise listening level gradually.
 */
#define TEST_AMPLITUDE 0.0316227766


static uint64_t monotonicNs(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;

    return ((uint64_t)ts.tv_sec * 1000000000ULL) +
           (uint64_t)ts.tv_nsec;
}

static void atomicUpdateMax(atomic_uint_fast64_t *target, uint64_t value)
{
    uint_fast64_t current =
        atomic_load_explicit(target, memory_order_relaxed);

    while (value > current &&
           !atomic_compare_exchange_weak_explicit(target,
                                                  &current,
                                                  value,
                                                  memory_order_relaxed,
                                                  memory_order_relaxed)) {
        /* current is refreshed by compare_exchange */
    }
}

static void atomicUpdateMinNonZero(atomic_uint_fast64_t *target,
                                   uint64_t value)
{
    if (value == 0)
        return;

    uint_fast64_t current =
        atomic_load_explicit(target, memory_order_relaxed);

    while ((current == 0 || value < current) &&
           !atomic_compare_exchange_weak_explicit(target,
                                                  &current,
                                                  value,
                                                  memory_order_relaxed,
                                                  memory_order_relaxed)) {
        /* current is refreshed by compare_exchange */
    }
}

static void put_s24_3le(uint8_t *dest, int32_t sample)
{
    uint32_t u = (uint32_t)sample;
    dest[0] = (uint8_t)(u & 0xFF);
    dest[1] = (uint8_t)((u >> 8) & 0xFF);
    dest[2] = (uint8_t)((u >> 16) & 0xFF);
}

/*
 * Reference Ploytec encoder from the current Linux v4 driver model:
 * one 4-channel S24_3LE PCM frame (12 bytes) -> 48 wire bytes.
 */
static void ploytec_encode_s24_3le(uint8_t *dest, const uint8_t *src)
{
    for (int i = 0; i < 8; i++) {
        /* Channels 1 & 3 */
        dest[i]      = (((src[2] >> (7 - i)) & 1) << 0) |
                       (((src[8] >> (7 - i)) & 1) << 1);
        dest[8 + i]  = (((src[1] >> (7 - i)) & 1) << 0) |
                       (((src[7] >> (7 - i)) & 1) << 1);
        dest[16 + i] = (((src[0] >> (7 - i)) & 1) << 0) |
                       (((src[6] >> (7 - i)) & 1) << 1);

        /* Channels 2 & 4 */
        dest[24 + i] = (((src[5] >> (7 - i)) & 1) << 0) |
                       (((src[11] >> (7 - i)) & 1) << 1);
        dest[32 + i] = (((src[4] >> (7 - i)) & 1) << 0) |
                       (((src[10] >> (7 - i)) & 1) << 1);
        dest[40 + i] = (((src[3] >> (7 - i)) & 1) << 0) |
                       (((src[9]  >> (7 - i)) & 1) << 1);
    }
}

typedef struct {
    uint64_t startFrame;
    uint64_t endFrame;
    int channel;          /* -1 = silence, otherwise 0..3 */
    double frequency;
    const char *label;
} AudioStage;

static const AudioStage kStages[] = {
    { 0,                         3 * SAMPLE_RATE,                  -1,   0.0, "3-second safety silence" },
    { 3 * SAMPLE_RATE,          (3 * SAMPLE_RATE) + 55125,         0, 440.0, "CH 1 tone -- expected MASTER LEFT" },
    { (3 * SAMPLE_RATE)+55125,  (3 * SAMPLE_RATE) + 77175,        -1,   0.0, "silence" },
    { (3 * SAMPLE_RATE)+77175,  (3 * SAMPLE_RATE) + 132300,        1, 550.0, "CH 2 tone -- expected MASTER RIGHT" },
    { (3 * SAMPLE_RATE)+132300, (3 * SAMPLE_RATE) + 154350,       -1,   0.0, "silence" },
    { (3 * SAMPLE_RATE)+154350, (3 * SAMPLE_RATE) + 209475,        2, 660.0, "CH 3 tone -- expected HEADPHONE LEFT" },
    { (3 * SAMPLE_RATE)+209475, (3 * SAMPLE_RATE) + 231525,       -1,   0.0, "silence" },
    { (3 * SAMPLE_RATE)+231525, (3 * SAMPLE_RATE) + 286650,        3, 880.0, "CH 4 tone -- expected HEADPHONE RIGHT" },
    { (3 * SAMPLE_RATE)+286650, (3 * SAMPLE_RATE) + 330750,       -1,   0.0, "final silence" }
};

#define STAGE_COUNT (sizeof(kStages) / sizeof(kStages[0]))
#define TEST_TOTAL_FRAMES ((uint64_t)((3 * SAMPLE_RATE) + 330750))

static int stage_for_frame(uint64_t frame)
{
    for (int i = 0; i < (int)STAGE_COUNT; i++) {
        if (frame >= kStages[i].startFrame && frame < kStages[i].endFrame)
            return i;
    }
    return -1;
}

static void fill_playback_batch(uint8_t *batch,
                                uint64_t *frameCursor,
                                int *lastPrintedStage)
{
    memset(batch, 0, BATCH_SIZE);

    const double twoPi = 6.28318530717958647692;
    const double fullScale = 8388607.0;
    const double amplitude = fullScale * TEST_AMPLITUDE;

    for (int p = 0; p < BATCH_PKTS; p++) {
        uint8_t *packet = batch + (p * PLOYTEC_PKT_SIZE);

        for (int f = 0; f < PLOYTEC_AUDIO_FRAMES_PER_PACKET; f++) {
            uint64_t frame = *frameCursor;
            int stage = stage_for_frame(frame);

            if (stage != *lastPrintedStage && stage >= 0) {
                printf("\nAUDIO STAGE: %s\n", kStages[stage].label);
                fflush(stdout);
                *lastPrintedStage = stage;
            }

            uint8_t pcm[PCM_FRAME_BYTES] = {0};

            if (stage >= 0 && kStages[stage].channel >= 0) {
                double t = (double)(frame - kStages[stage].startFrame) /
                           (double)SAMPLE_RATE;
                double x = sin(twoPi * kStages[stage].frequency * t);
                int32_t sample = (int32_t)(x * amplitude);

                put_s24_3le(pcm + (kStages[stage].channel * 3), sample);
            }

            ploytec_encode_s24_3le(packet + (f * PLOYTEC_AUDIO_FRAME_BYTES),
                                   pcm);

            (*frameCursor)++;
        }

        packet[MIDI_OUT_OFFSET] = MIDI_IDLE;
        packet[SYNC_OFFSET] = SYNC_VALUE;
        /* bytes 482..511 remain zero */
    }
}

static BOOL setConfig1(void)
{
    CFMutableDictionaryRef matching =
        [IOUSBHostDevice createMatchingDictionaryWithVendorID:@(VID)
                                                   productID:@(PID)
                                                   bcdDevice:nil
                                                 deviceClass:nil
                                              deviceSubclass:nil
                                              deviceProtocol:nil
                                                      speed:nil
                                             productIDArray:nil];
    if (!matching)
        return NO;

    io_service_t service =
        IOServiceGetMatchingService(kIOMainPortDefault, matching);

    if (service == IO_OBJECT_NULL)
        return NO;

    NSError *error = nil;

    IOUSBHostDevice *device =
        [[IOUSBHostDevice alloc]
            initWithIOService:service
            queue:nil
            error:&error
            interestHandler:nil];

    IOObjectRelease(service);

    if (!device) {
        fprintf(stderr, "ERROR opening USB device: %s\n",
                error ? error.localizedDescription.UTF8String : "unknown error");
        return NO;
    }

    BOOL ok = [device configureWithValue:1
                         matchInterfaces:YES
                                   error:&error];

    if (!ok) {
        fprintf(stderr, "ERROR selecting configuration 1: %s\n",
                error ? error.localizedDescription.UTF8String : "unknown error");
    }

    [device destroy];
    return ok;
}


static BOOL setConfig1WithRetry(void)
{
    /*
     * The Jockey can take a short time to re-publish its IOUSBHost service after
     * power-up / re-enumeration.  Do not make the user relaunch the program.
     */
    for (int attempt = 0; attempt < 30; attempt++) {
        if (setConfig1())
            return YES;

        usleep(100000);
    }

    return NO;
}

static IOUSBHostInterface *openInterface(NSUInteger number,
                                             dispatch_queue_t serviceQueue,
                                             NSError **error)
{
    CFMutableDictionaryRef matching =
        [IOUSBHostInterface
            createMatchingDictionaryWithVendorID:@(VID)
            productID:@(PID)
            bcdDevice:nil
            interfaceNumber:@(number)
            configurationValue:@(1)
            interfaceClass:nil
            interfaceSubclass:nil
            interfaceProtocol:nil
            speed:nil
            productIDArray:nil];

    if (!matching)
        return nil;

    io_service_t service =
        IOServiceGetMatchingService(kIOMainPortDefault, matching);

    if (service == IO_OBJECT_NULL)
        return nil;

    IOUSBHostInterface *interface =
        [[IOUSBHostInterface alloc]
            initWithIOService:service
            queue:serviceQueue
            error:error
            interestHandler:nil];

    IOObjectRelease(service);
    return interface;
}

static IOUSBHostInterface *openInterfaceWithRetry(NSUInteger number,
                                                      dispatch_queue_t serviceQueue)
{
    for (int attempt = 0; attempt < 30; attempt++) {
        NSError *error = nil;
        IOUSBHostInterface *interface =
            openInterface(number, serviceQueue, &error);

        if (interface)
            return interface;

        usleep(100000);
    }

    return nil;
}

static BOOL getStatus(IOUSBHostInterface *interface,
                      uint8_t *statusOut,
                      NSError **error)
{
    NSMutableData *data =
        [interface ioDataWithCapacity:1 error:error];

    if (!data)
        return NO;

    IOUSBDeviceRequest request = {
        .bmRequestType = 0xC0,
        .bRequest      = 0x49,
        .wValue        = 0,
        .wIndex        = 0,
        .wLength       = 1
    };

    NSUInteger transferred = 0;

    BOOL ok =
        [interface sendDeviceRequest:request
                                data:data
                    bytesTransferred:&transferred
                   completionTimeout:2.0
                               error:error];

    if (!ok || transferred != 1)
        return NO;

    *statusOut = ((const uint8_t *)data.bytes)[0];
    return YES;
}

static BOOL setStatus(IOUSBHostInterface *interface,
                      uint8_t status,
                      NSError **error)
{
    IOUSBDeviceRequest request = {
        .bmRequestType = 0x40,
        .bRequest      = 0x49,
        .wValue        = status,
        .wIndex        = 0,
        .wLength       = 0
    };

    return [interface sendDeviceRequest:request error:error];
}

static BOOL readFirmware(IOUSBHostInterface *interface, NSError **error)
{
    NSMutableData *fw =
        [interface ioDataWithCapacity:3 error:error];

    if (!fw)
        return NO;

    IOUSBDeviceRequest request = {
        .bmRequestType = 0xC0,
        .bRequest      = 0x56,
        .wValue        = 0,
        .wIndex        = 0,
        .wLength       = 3
    };

    NSUInteger transferred = 0;

    BOOL ok =
        [interface sendDeviceRequest:request
                                data:fw
                    bytesTransferred:&transferred
                   completionTimeout:2.0
                               error:error];

    if (!ok || transferred != 3)
        return NO;

    const uint8_t *b = fw.bytes;

    printf("Firmware: %u.%u.%u (raw %02x %02x %02x)\n",
           b[1], (b[2] >> 4) & 0x0F, b[2] & 0x0F,
           b[0], b[1], b[2]);

    return YES;
}

static BOOL getRate(IOUSBHostInterface *interface,
                    uint16_t index,
                    uint32_t *rateOut,
                    NSError **error)
{
    NSMutableData *data =
        [interface ioDataWithCapacity:3 error:error];

    if (!data)
        return NO;

    IOUSBDeviceRequest request = {
        .bmRequestType = 0xA2,
        .bRequest      = 0x81,
        .wValue        = 0x0100,
        .wIndex        = index,
        .wLength       = 3
    };

    NSUInteger transferred = 0;

    BOOL ok =
        [interface sendDeviceRequest:request
                                data:data
                    bytesTransferred:&transferred
                   completionTimeout:2.0
                               error:error];

    if (!ok || transferred != 3)
        return NO;

    const uint8_t *b = data.bytes;
    *rateOut = (uint32_t)b[0] |
               ((uint32_t)b[1] << 8) |
               ((uint32_t)b[2] << 16);

    return YES;
}

static BOOL writeRate(IOUSBHostInterface *interface,
                      uint16_t index,
                      uint32_t rate,
                      NSError **error)
{
    NSMutableData *data =
        [interface ioDataWithCapacity:3 error:error];

    if (!data)
        return NO;

    uint8_t *b = data.mutableBytes;
    b[0] = rate & 0xFF;
    b[1] = (rate >> 8) & 0xFF;
    b[2] = (rate >> 16) & 0xFF;

    IOUSBDeviceRequest request = {
        .bmRequestType = 0x22,
        .bRequest      = 0x01,
        .wValue        = 0x0100,
        .wIndex        = index,
        .wLength       = 3
    };

    NSUInteger transferred = 0;

    BOOL ok =
        [interface sendDeviceRequest:request
                                data:data
                    bytesTransferred:&transferred
                   completionTimeout:2.0
                               error:error];

    return ok && transferred == 3;
}

static BOOL selectAlt1AndClear(IOUSBHostInterface *if0,
                               IOUSBHostInterface *if1,
                               IOUSBHostPipe **pipe05Out,
                               IOUSBHostPipe **pipe83Out,
                               IOUSBHostPipe **pipe86Out)
{
    NSError *error = nil;

    if (![if0 selectAlternateSetting:1 error:&error]) {
        fprintf(stderr, "ERROR selecting interface 0 alt 1: %s\n",
                error.localizedDescription.UTF8String);
        return NO;
    }

    error = nil;

    if (![if1 selectAlternateSetting:1 error:&error]) {
        fprintf(stderr, "ERROR selecting interface 1 alt 1: %s\n",
                error.localizedDescription.UTF8String);
        return NO;
    }

    usleep(30);

    error = nil;
    IOUSBHostPipe *pipe05 = [if0 copyPipeWithAddress:0x05 error:&error];
    if (!pipe05) {
        fprintf(stderr, "ERROR opening 0x05: %s\n",
                error.localizedDescription.UTF8String);
        return NO;
    }

    error = nil;
    IOUSBHostPipe *pipe83 = [if0 copyPipeWithAddress:0x83 error:&error];
    if (!pipe83) {
        fprintf(stderr, "ERROR opening 0x83: %s\n",
                error.localizedDescription.UTF8String);
        return NO;
    }

    error = nil;
    IOUSBHostPipe *pipe86 = [if1 copyPipeWithAddress:0x86 error:&error];
    if (!pipe86) {
        fprintf(stderr, "ERROR opening 0x86: %s\n",
                error.localizedDescription.UTF8String);
        return NO;
    }

    IOUSBHostPipe *pipes[] = { pipe86, pipe05, pipe83 };
    const char *names[] = { "0x86", "0x05", "0x83" };

    for (int i = 0; i < 3; i++) {
        error = nil;
        if (![pipes[i] clearStallWithError:&error]) {
            fprintf(stderr, "ERROR clearing halt on %s: %s\n",
                    names[i],
                    error.localizedDescription.UTF8String);
            return NO;
        }
    }

    *pipe05Out = pipe05;
    *pipe83Out = pipe83;
    *pipe86Out = pipe86;

    printf("Interfaces alt 1 selected; pipes 0x05, 0x83, 0x86 ready.\n");
    return YES;
}


#define AUDIO_RING_FRAMES 32768
#define BLACKHOLE_NAME "BlackHole 16ch"
#define PLAYBACK_URB_COUNT 8
#define PLAYBACK_AUDIO_FRAMES (BATCH_PKTS * PLOYTEC_AUDIO_FRAMES_PER_PACKET)

/*
 * v6.2 recovery policy, adapted from the September 2026 Linux Jockey 3 driver:
 * - Linux can treat 20 ms of silence as authoritative because its URB completion
 *   timestamps are observed in-kernel.  Our IOUSBHost callbacks are delivered to
 *   a userspace dispatch queue, so a short scheduling delay can look identical to
 *   a hardware stall.
 * - Treat >=20 ms completion gaps that recover on their own as soft lateness:
 *   trim stale ring backlog immediately, but do NOT restart USB.
 * - Reserve the warm all-stream restart for playback that remains silent for
 *   >=60 ms.  This stays well below the 170.7 ms ring capacity and below the
 *   100-130 ms hard stalls seen in the earlier v4/v5 tests.
 *
 * The recovery implementation itself is unchanged from v6.1: abort all three
 * pipes asynchronously, rebuild the 8/8/1 request rings, prove playback healthy,
 * and resync the audio ring instead of replaying recovery-time audio late.
 */
#define SOFT_RESYNC_GAP_NS 20000000ULL
#define WATCHDOG_STALL_NS 60000000ULL
#define WATCHDOG_POLL_NS 5000000ULL
#define SERVICE_QUEUE_PROBE_NS 10000000ULL
#define SERVICE_QUEUE_PROBE_LEEWAY_NS 500000ULL
#define RECOVERY_GRACE_NS 200000000ULL
#define RECOVERY_MIN_COMPLETIONS 4UL
#define RECOVERY_PENDING_DRAIN_NS 250000000ULL
#define RECOVERY_LIVENESS_NS 8000000ULL
#define RECOVERY_CADENCE_FLOOR_NS 2500000ULL

/*
 * Adaptive clock servo:
 * keep a modest safety buffer while continuously matching BlackHole's
 * virtual clock to the Reloop's real playback clock.
 */
#define SERVO_TARGET_FRAMES 1024
#define PLAYBACK_PREFILL_FRAMES \
    (SERVO_TARGET_FRAMES + PLAYBACK_URB_COUNT * PLAYBACK_AUDIO_FRAMES)
/*
 * A warm recovery is an xrun-equivalent: sample continuity is already lost.
 * Keep enough pre-recovery audio to seed the fresh 8-request ring, survive the
 * four-completion health proof, and still land near the normal servo target.
 */
#define RECOVERY_RETAIN_FRAMES \
    (SERVO_TARGET_FRAMES + \
     (PLAYBACK_URB_COUNT + RECOVERY_MIN_COMPLETIONS) * PLAYBACK_AUDIO_FRAMES)
#define SERVO_INTERVAL_SECONDS 10
#define SERVO_DEPTH_RECOVERY_SECONDS 120.0
#define SERVO_MAX_DEPTH_BIAS_PPM 100.0
#define SERVO_MAX_ABS_PPM 500.0
#define SERVO_MAX_STEP_PPM 50.0
#define SERVO_MAX_MEASURED_MISMATCH_PPM 1000.0

/*
 * Emergency latency catch-up:
 * after a confirmed long synchronous USB write, temporarily slow BlackHole's
 * virtual source clock so the fixed-rate Reloop can consume the accumulated
 * backlog without deleting source audio.  BlackHole supports +/-1%; this test
 * deliberately caps the temporary correction at 0.3%.
 */
#define CATCHUP_TRIGGER_NS 50000000ULL
#define CATCHUP_EXIT_FRAMES (SERVO_TARGET_FRAMES + 256)
#define CATCHUP_TARGET_SECONDS 35.0
#define CATCHUP_MAX_SLOW_PPM 3000.0
#define CATCHUP_MIN_SLOW_PPM 300.0

static volatile sig_atomic_t gStop = 0;
static volatile sig_atomic_t gPhase4ManualPcmRequest = 0;

static void handleSignal(int sig)
{
    (void)sig;
    gStop = 1;
}

static void handlePhase4ManualPcmSignal(int sig)
{
    (void)sig;
    gPhase4ManualPcmRequest = 1;
}

typedef struct {
    float *frames; /* interleaved, first 4 BlackHole channels */
    atomic_uint_fast64_t writeFrame;
    atomic_uint_fast64_t readFrame;
    atomic_uint_fast64_t framesReceived;
    atomic_uint_fast64_t framesDropped;
    atomic_uint_fast64_t underrunFrames;
    atomic_uint_fast64_t maxDepthFrames;
    /* Frames intentionally skipped while a USB recovery is in progress. */
    atomic_uint_fast64_t recoveryInputFramesDiscarded;
    atomic_bool discardInputDuringRecovery;
    atomic_uint_fast64_t callbackCount;
    atomic_uint_fast64_t maxCallbackFrames;
    atomic_uint_fast64_t lastCallbackNs;
    atomic_uint_fast64_t maxCallbackGapNs;
    atomic_uint_fast64_t minCallbackGapNs;
    atomic_uint_fast64_t callbackGapOver20ms;
    atomic_uint_fast64_t callbackGapUnder5ms;
} AudioRing;

static BOOL audioRingInit(AudioRing *r)
{
    memset(r, 0, sizeof(*r));
    r->frames = calloc((size_t)AUDIO_RING_FRAMES * PCM_CHANNELS,
                       sizeof(float));
    if (!r->frames)
        return NO;

    atomic_init(&r->writeFrame, 0);
    atomic_init(&r->readFrame, 0);
    atomic_init(&r->framesReceived, 0);
    atomic_init(&r->framesDropped, 0);
    atomic_init(&r->underrunFrames, 0);
    atomic_init(&r->maxDepthFrames, 0);
    atomic_init(&r->recoveryInputFramesDiscarded, 0);
    atomic_init(&r->discardInputDuringRecovery, false);
    atomic_init(&r->callbackCount, 0);
    atomic_init(&r->maxCallbackFrames, 0);
    atomic_init(&r->lastCallbackNs, 0);
    atomic_init(&r->maxCallbackGapNs, 0);
    atomic_init(&r->minCallbackGapNs, 0);
    atomic_init(&r->callbackGapOver20ms, 0);
    atomic_init(&r->callbackGapUnder5ms, 0);
    return YES;
}

static void audioRingDestroy(AudioRing *r)
{
    free(r->frames);
    r->frames = NULL;
}

static uint64_t audioRingDepth(AudioRing *r)
{
    uint64_t w = atomic_load_explicit(&r->writeFrame, memory_order_acquire);
    uint64_t rd = atomic_load_explicit(&r->readFrame, memory_order_acquire);
    return w - rd;
}

static uint64_t audioRingTrimOldestToDepth(AudioRing *r, uint64_t targetDepth)
{
    uint64_t rd =
        atomic_load_explicit(&r->readFrame, memory_order_relaxed);
    uint64_t w =
        atomic_load_explicit(&r->writeFrame, memory_order_acquire);
    uint64_t depth = w - rd;

    if (depth <= targetDepth)
        return 0;

    uint64_t discard = depth - targetDepth;
    atomic_store_explicit(&r->readFrame,
                          rd + discard,
                          memory_order_release);
    return discard;
}

static float sampleFromABL(const AudioBufferList *abl,
                           UInt32 frame,
                           UInt32 targetChannel)
{
    UInt32 firstChannel = 0;

    for (UInt32 b = 0; b < abl->mNumberBuffers; b++) {
        const AudioBuffer *buf = &abl->mBuffers[b];
        UInt32 channels = buf->mNumberChannels;

        if (targetChannel >= firstChannel &&
            targetChannel < firstChannel + channels) {

            if (!buf->mData)
                return 0.0f;

            UInt32 localChannel = targetChannel - firstChannel;
            const float *samples = (const float *)buf->mData;

            /*
             * BlackHole exposes 32-bit float PCM.  This handles both
             * one-buffer-per-channel and interleaved groups.
             */
            return samples[(size_t)frame * channels + localChannel];
        }

        firstChannel += channels;
    }

    return 0.0f;
}

static OSStatus blackHoleIOProc(AudioObjectID inDevice,
                                const AudioTimeStamp *inNow,
                                const AudioBufferList *inInputData,
                                const AudioTimeStamp *inInputTime,
                                AudioBufferList *outOutputData,
                                const AudioTimeStamp *inOutputTime,
                                void *inClientData)
{
    (void)inDevice;
    (void)inNow;
    (void)inInputTime;
    (void)outOutputData;
    (void)inOutputTime;

    AudioRing *r = (AudioRing *)inClientData;

    if (!inInputData || !r || !r->frames)
        return noErr;

    /*
     * Determine frame count from the first non-empty buffer.
     * BlackHole is Float32, so bytes / (channels * 4) = frames.
     */
    UInt32 frameCount = 0;

    for (UInt32 b = 0; b < inInputData->mNumberBuffers; b++) {
        const AudioBuffer *buf = &inInputData->mBuffers[b];
        if (buf->mData && buf->mNumberChannels > 0) {
            frameCount =
                buf->mDataByteSize /
                (buf->mNumberChannels * (UInt32)sizeof(float));
            break;
        }
    }

    if (frameCount == 0)
        return noErr;

    atomic_fetch_add_explicit(&r->callbackCount,
                              1,
                              memory_order_relaxed);

    uint64_t callbackNowNs = monotonicNs();
    uint64_t previousCallbackNs =
        atomic_exchange_explicit(&r->lastCallbackNs,
                                 callbackNowNs,
                                 memory_order_relaxed);

    if (previousCallbackNs != 0 && callbackNowNs > previousCallbackNs) {
        uint64_t callbackGapNs = callbackNowNs - previousCallbackNs;

        atomicUpdateMax(&r->maxCallbackGapNs, callbackGapNs);
        atomicUpdateMinNonZero(&r->minCallbackGapNs, callbackGapNs);

        if (callbackGapNs > 20000000ULL)
            atomic_fetch_add_explicit(&r->callbackGapOver20ms,
                                      1,
                                      memory_order_relaxed);

        if (callbackGapNs < 5000000ULL)
            atomic_fetch_add_explicit(&r->callbackGapUnder5ms,
                                      1,
                                      memory_order_relaxed);
    }

    uint64_t previousMax =
        atomic_load_explicit(&r->maxCallbackFrames,
                             memory_order_relaxed);
    if ((uint64_t)frameCount > previousMax) {
        atomic_store_explicit(&r->maxCallbackFrames,
                              frameCount,
                              memory_order_relaxed);
    }

    /*
     * During a USB warm recovery there is no useful real-time sink.  Keeping
     * these frames would replay stale audio after the controller recovers and
     * permanently add the outage duration to monitoring/master latency.  The
     * Linux driver reports an xrun at this point; our userspace equivalent is
     * to keep CoreAudio running but intentionally skip input until USB is live.
     */
    if (atomic_load_explicit(&r->discardInputDuringRecovery,
                             memory_order_acquire)) {
        atomic_fetch_add_explicit(&r->recoveryInputFramesDiscarded,
                                  frameCount,
                                  memory_order_relaxed);
        return noErr;
    }

    uint64_t w =
        atomic_load_explicit(&r->writeFrame, memory_order_relaxed);
    uint64_t rd =
        atomic_load_explicit(&r->readFrame, memory_order_acquire);

    uint64_t used = w - rd;
    uint64_t available =
        used < AUDIO_RING_FRAMES ? AUDIO_RING_FRAMES - used : 0;

    UInt32 accepted = frameCount;
    if ((uint64_t)accepted > available)
        accepted = (UInt32)available;

    for (UInt32 f = 0; f < accepted; f++) {
        uint64_t slot = (w + f) % AUDIO_RING_FRAMES;
        float *dst = r->frames + slot * PCM_CHANNELS;

        for (UInt32 ch = 0; ch < PCM_CHANNELS; ch++)
            dst[ch] = sampleFromABL(inInputData, f, ch);
    }

    if (accepted > 0) {
        atomic_store_explicit(&r->writeFrame,
                              w + accepted,
                              memory_order_release);
        atomic_fetch_add_explicit(&r->framesReceived,
                                  accepted,
                                  memory_order_relaxed);

        uint64_t newDepth = (w + accepted) - rd;
        atomicUpdateMax(&r->maxDepthFrames, newDepth);
    }

    if (accepted < frameCount) {
        atomic_fetch_add_explicit(&r->framesDropped,
                                  frameCount - accepted,
                                  memory_order_relaxed);
    }

    return noErr;
}

static BOOL audioRingPop(AudioRing *r, float out[PCM_CHANNELS])
{
    uint64_t rd =
        atomic_load_explicit(&r->readFrame, memory_order_relaxed);
    uint64_t w =
        atomic_load_explicit(&r->writeFrame, memory_order_acquire);

    if (rd >= w) {
        for (int ch = 0; ch < PCM_CHANNELS; ch++)
            out[ch] = 0.0f;

        atomic_fetch_add_explicit(&r->underrunFrames,
                                  1,
                                  memory_order_relaxed);
        return NO;
    }

    uint64_t slot = rd % AUDIO_RING_FRAMES;
    const float *src = r->frames + slot * PCM_CHANNELS;

    for (int ch = 0; ch < PCM_CHANNELS; ch++)
        out[ch] = src[ch];

    atomic_store_explicit(&r->readFrame,
                          rd + 1,
                          memory_order_release);
    return YES;
}

/*
 * Phase 4 diagnostic PCM capture.
 *
 * Keep a rolling copy of the exact four-channel Float32 source frames consumed
 * by the playback thread immediately before conversion/USB packetization.
 * There is no file I/O, allocation, locking or Foundation work on the real-time
 * path.  A slow USB write only publishes a small trigger record.  The ordinary
 * main thread waits for the post-event window, then writes the PCM snapshot.
 *
 * 20 seconds of four-channel Float32 @ 48 kHz is ~15.4 MB.  Each saved event is
 * a 10-second (5 s before + 5 s after) IEEE-float WAV, ~7.7 MB.
 */
#define PHASE4_PCM_RING_SECONDS 20u
#define PHASE4_PCM_PRE_SECONDS 5u
#define PHASE4_PCM_POST_SECONDS 5u
#define PHASE4_PCM_RING_FRAMES ((uint64_t)SAMPLE_RATE * PHASE4_PCM_RING_SECONDS)
#define PHASE4_PCM_TRIGGER_CAPACITY 16u

typedef struct {
    float frames[PHASE4_PCM_RING_FRAMES * PCM_CHANNELS];
    atomic_uint_fast64_t writeFrame;
} Phase4PcmRing;

typedef struct {
    uint64_t sequence;
    uint64_t eventEndNs;
    uint64_t writeDurationNs;
    uint64_t centerFrame;
} Phase4PcmTrigger;

typedef struct {
    Phase4PcmTrigger items[PHASE4_PCM_TRIGGER_CAPACITY];
    atomic_uint_fast64_t writeIndex;
    atomic_uint_fast64_t readIndex;
    atomic_uint_fast64_t dropped;
} Phase4PcmTriggerRing;

static Phase4PcmRing gPhase4PcmRing;
static Phase4PcmTriggerRing gPhase4PcmTriggers;
static atomic_uint_fast64_t gPhase4PcmTriggerSequence;

#define PHASE4_EVENT_RING_CAPACITY 64u

typedef struct {
    uint64_t sequence;
    uint64_t eventEndNs;
    uint64_t writeDurationNs;
    uint64_t completionGapNs;
    uint64_t ringDepthFrames;
    unsigned long bytesTransferred;
    unsigned long attempt;
    bool success;
    uint64_t bhCallbackAgeNs;
    uint64_t captureSuccessAgeNs;
    uint64_t midiSuccessAgeNs;
    uint64_t if0ProbeAgeNs;
    uint64_t if1ProbeAgeNs;
    uint64_t recoveryProbeAgeNs;
} Phase4PlaybackDiagEvent;

typedef struct {
    Phase4PlaybackDiagEvent items[PHASE4_EVENT_RING_CAPACITY];
    atomic_uint_fast64_t writeIndex;
    atomic_uint_fast64_t readIndex;
    atomic_uint_fast64_t dropped;
} Phase4PlaybackDiagRing;

typedef struct {
    uint64_t sequence;
    uint64_t eventEndNs;
    uint64_t durationNs;
    unsigned long bytesTransferred;
    bool success;
    uint64_t playbackSuccessAgeNs;
    uint64_t bhCallbackAgeNs;
    uint64_t midiSuccessAgeNs;
} Phase4CaptureDiagEvent;

typedef struct {
    Phase4CaptureDiagEvent items[PHASE4_EVENT_RING_CAPACITY];
    atomic_uint_fast64_t writeIndex;
    atomic_uint_fast64_t readIndex;
    atomic_uint_fast64_t dropped;
} Phase4CaptureDiagRing;

typedef struct {
    uint64_t sequence;
    uint64_t eventNs;
    int status;
} Phase4MidiErrorEvent;

typedef struct {
    Phase4MidiErrorEvent items[PHASE4_EVENT_RING_CAPACITY];
    atomic_uint_fast64_t writeIndex;
    atomic_uint_fast64_t readIndex;
    atomic_uint_fast64_t dropped;
} Phase4MidiErrorRing;

static Phase4PlaybackDiagRing gPhase4PlaybackEvents;
static Phase4CaptureDiagRing gPhase4CaptureEvents;
static Phase4MidiErrorRing gPhase4MidiErrorEvents;

static void phase4EventRingsInit(void)
{
    memset(&gPhase4PlaybackEvents, 0, sizeof(gPhase4PlaybackEvents));
    memset(&gPhase4CaptureEvents, 0, sizeof(gPhase4CaptureEvents));
    memset(&gPhase4MidiErrorEvents, 0, sizeof(gPhase4MidiErrorEvents));
    atomic_init(&gPhase4PlaybackEvents.writeIndex, 0);
    atomic_init(&gPhase4PlaybackEvents.readIndex, 0);
    atomic_init(&gPhase4PlaybackEvents.dropped, 0);
    atomic_init(&gPhase4CaptureEvents.writeIndex, 0);
    atomic_init(&gPhase4CaptureEvents.readIndex, 0);
    atomic_init(&gPhase4CaptureEvents.dropped, 0);
    atomic_init(&gPhase4MidiErrorEvents.writeIndex, 0);
    atomic_init(&gPhase4MidiErrorEvents.readIndex, 0);
    atomic_init(&gPhase4MidiErrorEvents.dropped, 0);
}

static void phase4PlaybackEventPush(const Phase4PlaybackDiagEvent *event)
{
    uint64_t wr = atomic_load_explicit(&gPhase4PlaybackEvents.writeIndex,
                                       memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&gPhase4PlaybackEvents.readIndex,
                                       memory_order_acquire);
    if (wr - rd >= PHASE4_EVENT_RING_CAPACITY) {
        atomic_fetch_add_explicit(&gPhase4PlaybackEvents.dropped, 1,
                                  memory_order_relaxed);
        return;
    }
    Phase4PlaybackDiagEvent copy = *event;
    copy.sequence = wr + 1;
    gPhase4PlaybackEvents.items[wr % PHASE4_EVENT_RING_CAPACITY] = copy;
    atomic_store_explicit(&gPhase4PlaybackEvents.writeIndex, wr + 1,
                          memory_order_release);
}

static BOOL phase4PlaybackEventPop(Phase4PlaybackDiagEvent *out)
{
    uint64_t rd = atomic_load_explicit(&gPhase4PlaybackEvents.readIndex,
                                       memory_order_relaxed);
    uint64_t wr = atomic_load_explicit(&gPhase4PlaybackEvents.writeIndex,
                                       memory_order_acquire);
    if (rd >= wr)
        return NO;
    *out = gPhase4PlaybackEvents.items[rd % PHASE4_EVENT_RING_CAPACITY];
    atomic_store_explicit(&gPhase4PlaybackEvents.readIndex, rd + 1,
                          memory_order_release);
    return YES;
}

static void phase4CaptureEventPush(const Phase4CaptureDiagEvent *event)
{
    uint64_t wr = atomic_load_explicit(&gPhase4CaptureEvents.writeIndex,
                                       memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&gPhase4CaptureEvents.readIndex,
                                       memory_order_acquire);
    if (wr - rd >= PHASE4_EVENT_RING_CAPACITY) {
        atomic_fetch_add_explicit(&gPhase4CaptureEvents.dropped, 1,
                                  memory_order_relaxed);
        return;
    }
    Phase4CaptureDiagEvent copy = *event;
    copy.sequence = wr + 1;
    gPhase4CaptureEvents.items[wr % PHASE4_EVENT_RING_CAPACITY] = copy;
    atomic_store_explicit(&gPhase4CaptureEvents.writeIndex, wr + 1,
                          memory_order_release);
}

static BOOL phase4CaptureEventPop(Phase4CaptureDiagEvent *out)
{
    uint64_t rd = atomic_load_explicit(&gPhase4CaptureEvents.readIndex,
                                       memory_order_relaxed);
    uint64_t wr = atomic_load_explicit(&gPhase4CaptureEvents.writeIndex,
                                       memory_order_acquire);
    if (rd >= wr)
        return NO;
    *out = gPhase4CaptureEvents.items[rd % PHASE4_EVENT_RING_CAPACITY];
    atomic_store_explicit(&gPhase4CaptureEvents.readIndex, rd + 1,
                          memory_order_release);
    return YES;
}

static void phase4MidiErrorPush(uint64_t eventNs, int status)
{
    uint64_t wr = atomic_load_explicit(&gPhase4MidiErrorEvents.writeIndex,
                                       memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&gPhase4MidiErrorEvents.readIndex,
                                       memory_order_acquire);
    if (wr - rd >= PHASE4_EVENT_RING_CAPACITY) {
        atomic_fetch_add_explicit(&gPhase4MidiErrorEvents.dropped, 1,
                                  memory_order_relaxed);
        return;
    }
    Phase4MidiErrorEvent event = {
        .sequence = wr + 1,
        .eventNs = eventNs,
        .status = status
    };
    gPhase4MidiErrorEvents.items[wr % PHASE4_EVENT_RING_CAPACITY] = event;
    atomic_store_explicit(&gPhase4MidiErrorEvents.writeIndex, wr + 1,
                          memory_order_release);
}

static BOOL phase4MidiErrorPop(Phase4MidiErrorEvent *out)
{
    uint64_t rd = atomic_load_explicit(&gPhase4MidiErrorEvents.readIndex,
                                       memory_order_relaxed);
    uint64_t wr = atomic_load_explicit(&gPhase4MidiErrorEvents.writeIndex,
                                       memory_order_acquire);
    if (rd >= wr)
        return NO;
    *out = gPhase4MidiErrorEvents.items[rd % PHASE4_EVENT_RING_CAPACITY];
    atomic_store_explicit(&gPhase4MidiErrorEvents.readIndex, rd + 1,
                          memory_order_release);
    return YES;
}

static void phase4PcmInit(void)
{
    memset(&gPhase4PcmRing, 0, sizeof(gPhase4PcmRing));
    memset(&gPhase4PcmTriggers, 0, sizeof(gPhase4PcmTriggers));
    atomic_init(&gPhase4PcmRing.writeFrame, 0);
    atomic_init(&gPhase4PcmTriggers.writeIndex, 0);
    atomic_init(&gPhase4PcmTriggers.readIndex, 0);
    atomic_init(&gPhase4PcmTriggers.dropped, 0);
    atomic_init(&gPhase4PcmTriggerSequence, 0);
}

static void phase4PcmTriggerPush(uint64_t eventEndNs,
                                 uint64_t writeDurationNs,
                                 uint64_t centerFrame)
{
    uint64_t wr = atomic_load_explicit(&gPhase4PcmTriggers.writeIndex,
                                       memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&gPhase4PcmTriggers.readIndex,
                                       memory_order_acquire);

    if (wr - rd >= PHASE4_PCM_TRIGGER_CAPACITY) {
        atomic_fetch_add_explicit(&gPhase4PcmTriggers.dropped,
                                  1,
                                  memory_order_relaxed);
        return;
    }

    Phase4PcmTrigger *event =
        &gPhase4PcmTriggers.items[wr % PHASE4_PCM_TRIGGER_CAPACITY];
    event->sequence =
        atomic_fetch_add_explicit(&gPhase4PcmTriggerSequence,
                                  1,
                                  memory_order_relaxed) + 1;
    event->eventEndNs = eventEndNs;
    event->writeDurationNs = writeDurationNs;
    event->centerFrame = centerFrame;

    atomic_store_explicit(&gPhase4PcmTriggers.writeIndex,
                          wr + 1,
                          memory_order_release);
}

static BOOL phase4PcmTriggerPeek(Phase4PcmTrigger *out)
{
    uint64_t rd = atomic_load_explicit(&gPhase4PcmTriggers.readIndex,
                                       memory_order_relaxed);
    uint64_t wr = atomic_load_explicit(&gPhase4PcmTriggers.writeIndex,
                                       memory_order_acquire);
    if (rd >= wr)
        return NO;

    *out = gPhase4PcmTriggers.items[rd % PHASE4_PCM_TRIGGER_CAPACITY];
    return YES;
}

static void phase4PcmTriggerPop(void)
{
    uint64_t rd = atomic_load_explicit(&gPhase4PcmTriggers.readIndex,
                                       memory_order_relaxed);
    atomic_store_explicit(&gPhase4PcmTriggers.readIndex,
                          rd + 1,
                          memory_order_release);
}

static void phase4WriteLe16(FILE *f, uint16_t value)
{
    uint8_t b[2] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff)
    };
    (void)fwrite(b, 1, sizeof(b), f);
}

static void phase4WriteLe32(FILE *f, uint32_t value)
{
    uint8_t b[4] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff)
    };
    (void)fwrite(b, 1, sizeof(b), f);
}

/*
 * Return values:
 *   1  snapshot written
 *   0  event is valid but its post-event PCM has not arrived yet
 *  -1  event window expired/was overwritten
 *  -2  file/directory write failure
 */
static int phase4WritePcmSnapshot(const Phase4PcmTrigger *event,
                                  const char *directory,
                                  uint64_t diagnosticSessionStartNs)
{
    const uint64_t preFrames =
        (uint64_t)SAMPLE_RATE * PHASE4_PCM_PRE_SECONDS;
    const uint64_t postFrames =
        (uint64_t)SAMPLE_RATE * PHASE4_PCM_POST_SECONDS;

    uint64_t current =
        atomic_load_explicit(&gPhase4PcmRing.writeFrame,
                             memory_order_acquire);
    uint64_t start = event->centerFrame > preFrames
        ? event->centerFrame - preFrames : 0;
    uint64_t end = event->centerFrame + postFrames;

    if (current < end)
        return 0;

    uint64_t oldest = current > PHASE4_PCM_RING_FRAMES
        ? current - PHASE4_PCM_RING_FRAMES : 0;
    if (start < oldest)
        return -1;

    if (mkdir(directory, 0755) != 0 && errno != EEXIST)
        return -2;

    const BOOL manualTrigger = event->writeDurationNs == 0;
    const char *capturePrefix = manualTrigger ? "manual_pcm" : "usb_stall";

    char wavPath[PATH_MAX];
    char metaPath[PATH_MAX];
    snprintf(wavPath,
             sizeof(wavPath),
             "%s/%s_%06llu.wav",
             directory,
             capturePrefix,
             (unsigned long long)event->sequence);
    snprintf(metaPath,
             sizeof(metaPath),
             "%s/%s_%06llu.json",
             directory,
             capturePrefix,
             (unsigned long long)event->sequence);

    uint64_t frameCount = end - start;
    uint64_t dataBytes64 = frameCount * PCM_CHANNELS * sizeof(float);
    if (dataBytes64 > UINT32_MAX)
        return -2;
    uint32_t dataBytes = (uint32_t)dataBytes64;

    /*
     * Copy the ready window out of the rolling ring before any disk I/O.
     * At the first ready point the 20-second ring leaves a 10-second overwrite
     * margin behind this 10-second window.  Copying ~7.7 MB should take far
     * less than that, and the post-copy writeFrame check detects if it did not.
     */
    float *snapshot = (float *)malloc((size_t)dataBytes);
    if (!snapshot)
        return -2;

    uint64_t frame = start;
    size_t snapshotFloatOffset = 0;
    while (frame < end) {
        uint64_t slot = frame % PHASE4_PCM_RING_FRAMES;
        uint64_t contiguous = PHASE4_PCM_RING_FRAMES - slot;
        uint64_t remaining = end - frame;
        if (contiguous > remaining)
            contiguous = remaining;

        size_t floats = (size_t)contiguous * PCM_CHANNELS;
        memcpy(snapshot + snapshotFloatOffset,
               &gPhase4PcmRing.frames[slot * PCM_CHANNELS],
               floats * sizeof(float));
        snapshotFloatOffset += floats;
        frame += contiguous;
    }

    uint64_t afterCopy =
        atomic_load_explicit(&gPhase4PcmRing.writeFrame,
                             memory_order_acquire);
    if (afterCopy > start &&
        afterCopy - start > PHASE4_PCM_RING_FRAMES) {
        free(snapshot);
        return -1;
    }

    double channelPeak[PCM_CHANNELS] = {0};
    uint64_t nonzeroFrames = 0;
    for (uint64_t i = 0; i < frameCount; i++) {
        BOOL frameNonzero = NO;
        for (int ch = 0; ch < PCM_CHANNELS; ch++) {
            float value = snapshot[i * PCM_CHANNELS + ch];
            double magnitude = fabs((double)value);
            if (magnitude > channelPeak[ch])
                channelPeak[ch] = magnitude;
            if (value != 0.0f)
                frameNonzero = YES;
        }
        if (frameNonzero)
            nonzeroFrames++;
    }

    FILE *wav = fopen(wavPath, "wb");
    if (!wav) {
        free(snapshot);
        return -2;
    }

    /* Standard 44-byte WAVE_FORMAT_IEEE_FLOAT header. */
    (void)fwrite("RIFF", 1, 4, wav);
    phase4WriteLe32(wav, 36u + dataBytes);
    (void)fwrite("WAVE", 1, 4, wav);
    (void)fwrite("fmt ", 1, 4, wav);
    phase4WriteLe32(wav, 16u);
    phase4WriteLe16(wav, 3u); /* IEEE float */
    phase4WriteLe16(wav, PCM_CHANNELS);
    phase4WriteLe32(wav, SAMPLE_RATE);
    phase4WriteLe32(wav,
                    SAMPLE_RATE * PCM_CHANNELS * (uint32_t)sizeof(float));
    phase4WriteLe16(wav, PCM_CHANNELS * (uint16_t)sizeof(float));
    phase4WriteLe16(wav, 32u);
    (void)fwrite("data", 1, 4, wav);
    phase4WriteLe32(wav, dataBytes);

    size_t totalFloats = (size_t)frameCount * PCM_CHANNELS;
    if (fwrite(snapshot, sizeof(float), totalFloats, wav) != totalFloats) {
        free(snapshot);
        fclose(wav);
        return -2;
    }
    free(snapshot);

    if (fclose(wav) != 0)
        return -2;

    FILE *meta = fopen(metaPath, "w");
    if (meta) {
        double tSeconds =
            event->eventEndNs > diagnosticSessionStartNs
                ? (double)(event->eventEndNs - diagnosticSessionStartNs) / 1e9
                : 0.0;
        fprintf(meta,
                "{\n"
                "  \"candidate\": \"v8.0.7\",\n"
                "  \"trigger\": \"%s\",\n"
                "  \"event_sequence\": %llu,\n"
                "  \"event_t_plus_seconds\": %.6f,\n"
                "  \"usb_write_duration_ms\": %.6f,\n"
                "  \"sample_rate\": %u,\n"
                "  \"channels\": %u,\n"
                "  \"format\": \"IEEE Float32 little-endian WAV\",\n"
                "  \"capture_point\": \"source PCM consumed immediately before USB packetization/submission\",\n"
                "  \"pre_seconds\": %u,\n"
                "  \"post_seconds\": %u,\n"
                "  \"event_offset_seconds_in_wav\": %.3f,\n"
                "  \"center_frame\": %llu,\n"
                "  \"nonzero_frames\": %llu,\n"
                "  \"channel_peak_abs\": [%.9f, %.9f, %.9f, %.9f]\n"
                "}\n",
                manualTrigger ? "manual" : "usb_stall",
                (unsigned long long)event->sequence,
                tSeconds,
                (double)event->writeDurationNs / 1e6,
                (unsigned)SAMPLE_RATE,
                (unsigned)PCM_CHANNELS,
                (unsigned)PHASE4_PCM_PRE_SECONDS,
                (unsigned)PHASE4_PCM_POST_SECONDS,
                (double)PHASE4_PCM_PRE_SECONDS,
                (unsigned long long)event->centerFrame,
                (unsigned long long)nonzeroFrames,
                channelPeak[0],
                channelPeak[1],
                channelPeak[2],
                channelPeak[3]);
        fclose(meta);
    }

    printf("PCM DIAG SAVED #%llu: %s (%s trigger, nonzero frames %llu/%llu, peaks %.6f/%.6f/%.6f/%.6f).\n",
           (unsigned long long)event->sequence,
           wavPath,
           manualTrigger ? "manual" : "USB stall",
           (unsigned long long)nonzeroFrames,
           (unsigned long long)frameCount,
           channelPeak[0],
           channelPeak[1],
           channelPeak[2],
           channelPeak[3]);
    fflush(stdout);
    return 1;
}

static int32_t floatToS24(float x)
{
    if (x > 1.0f) x = 1.0f;
    if (x < -1.0f) x = -1.0f;

    double scaled = (double)x * 8388607.0;

    if (scaled >= 0.0)
        return (int32_t)(scaled + 0.5);
    else
        return (int32_t)(scaled - 0.5);
}

static void fillPlaybackFromRing(uint8_t *batch, AudioRing *ring)
{
    memset(batch, 0, BATCH_SIZE);

    uint64_t diagnosticBase =
        atomic_load_explicit(&gPhase4PcmRing.writeFrame,
                             memory_order_relaxed);
    uint64_t diagnosticOffset = 0;

    for (int p = 0; p < BATCH_PKTS; p++) {
        uint8_t *packet = batch + p * PLOYTEC_PKT_SIZE;

        for (int f = 0; f < PLOYTEC_AUDIO_FRAMES_PER_PACKET; f++) {
            float in[PCM_CHANNELS] = {0};
            uint8_t pcm[PCM_FRAME_BYTES] = {0};

            audioRingPop(ring, in);

            uint64_t diagnosticSlot =
                (diagnosticBase + diagnosticOffset) % PHASE4_PCM_RING_FRAMES;
            float *diagnosticDst =
                &gPhase4PcmRing.frames[diagnosticSlot * PCM_CHANNELS];
            for (int ch = 0; ch < PCM_CHANNELS; ch++)
                diagnosticDst[ch] = in[ch];
            diagnosticOffset++;

            for (int ch = 0; ch < PCM_CHANNELS; ch++)
                put_s24_3le(pcm + ch * 3, floatToS24(in[ch]));

            ploytec_encode_s24_3le(
                packet + f * PLOYTEC_AUDIO_FRAME_BYTES,
                pcm);
        }

        packet[MIDI_OUT_OFFSET] = MIDI_IDLE;
        packet[SYNC_OFFSET] = SYNC_VALUE;
    }

    /* Publish the full block only after all PCM samples have been copied. */
    atomic_store_explicit(&gPhase4PcmRing.writeFrame,
                          diagnosticBase + diagnosticOffset,
                          memory_order_release);
}


typedef struct {
    void *pipeObject;
    void *bufferObject;
    AudioRing *ring;
    atomic_bool *workerStop;
    atomic_bool *playbackFatal;
    atomic_ulong *playbackTransfers;
    atomic_ulong *playbackErrors;
    atomic_ulong *playbackPending;
    atomic_uint_fast64_t *lastPlaybackCompletionNs;
    atomic_uint_fast64_t *lastPlaybackSuccessNs;
    atomic_uint_fast64_t *maxPlaybackCompletionGapNs;
    atomic_uint_fast64_t *playbackGapOver10ms;
    atomic_uint_fast64_t *playbackGapOver50ms;
    atomic_uint_fast64_t *maxPlaybackRefillDelayNs;
    atomic_uint_fast64_t *maxSyncWriteDurationNs;
    atomic_ulong *syncWriteOver10ms;
    atomic_ulong *syncWriteOver20ms;
    atomic_ulong *syncWriteOver50ms;
    atomic_ulong *playbackTimeouts;
    atomic_ulong *playbackOtherErrors;
    atomic_ulong *playbackPartialTransfers;
    atomic_int *playbackLastOtherStatus;
    /* v8.0.7 diagnostic-only: operational slow-write event snapshots. */
    atomic_ulong *slowWriteOperationalOver20ms;
    atomic_ulong *slowWriteOperationalOver50ms;
    atomic_uint_fast64_t *lastSlowWriteEndNs;
    atomic_uint_fast64_t *lastSlowWriteDurationNs;
    atomic_uint_fast64_t *lastSlowWriteCompletionGapNs;
    atomic_uint_fast64_t *lastSlowWriteRingDepthFrames;
    atomic_ulong *lastSlowWriteBytes;
    atomic_ulong *lastSlowWriteAttempt;
    atomic_bool *lastSlowWriteSuccess;
    atomic_uint_fast64_t *lastSlowWriteBhCallbackAgeNs;
    atomic_uint_fast64_t *lastSlowWriteCaptureSuccessAgeNs;
    atomic_uint_fast64_t *lastSlowWriteMidiSuccessAgeNs;
    atomic_uint_fast64_t *lastSlowWriteIf0ProbeAgeNs;
    atomic_uint_fast64_t *lastSlowWriteIf1ProbeAgeNs;
    atomic_uint_fast64_t *lastSlowWriteRecoveryProbeAgeNs;
    atomic_uint_fast64_t *lastCaptureSuccessNs;
    atomic_uint_fast64_t *lastMidiSuccessNs;
    atomic_uint_fast64_t *if0ProbeLastNs;
    atomic_uint_fast64_t *if1ProbeLastNs;
    atomic_uint_fast64_t *recoveryProbeLastNs;
    atomic_ulong *softResyncCount;
    atomic_uint_fast64_t *softResyncFramesDiscarded;
    atomic_bool *catchupRequested;
    MidiOutRing *midiOutRing;
    atomic_int *realtimePolicyResult;
} RealtimePlaybackContext;

static uint32_t machTicksForNanoseconds(uint64_t ns)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    __uint128_t ticks = (__uint128_t)ns * tb.denom / tb.numer;
    if (ticks > UINT32_MAX)
        ticks = UINT32_MAX;
    return (uint32_t)ticks;
}

static kern_return_t makeCurrentThreadRealtime(void)
{
    /*
     * One 4096-byte Ploytec batch carries 80 audio frames = 1.667 ms.
     * Give the playback pthread a real-time time constraint so app launches,
     * browser work, memory pressure, etc. cannot starve it like ordinary GCD.
     * The computation budget is deliberately small; the thread spends most of
     * each cycle blocked inside the synchronous USB transfer.
     */
    thread_time_constraint_policy_data_t policy;
    policy.period = machTicksForNanoseconds(1666667ULL);
    policy.computation = machTicksForNanoseconds(400000ULL);
    policy.constraint = machTicksForNanoseconds(800000ULL);
    policy.preemptible = TRUE;

    return thread_policy_set(pthread_mach_thread_np(pthread_self()),
                             THREAD_TIME_CONSTRAINT_POLICY,
                             (thread_policy_t)&policy,
                             THREAD_TIME_CONSTRAINT_POLICY_COUNT);
}

static void *realtimePlaybackThreadMain(void *opaque)
{
    RealtimePlaybackContext *ctx = (RealtimePlaybackContext *)opaque;

    @autoreleasepool {
        pthread_setname_np("reloop.rt.playback");
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

        kern_return_t rt = makeCurrentThreadRealtime();
        atomic_store(ctx->realtimePolicyResult, (int)rt);

        IOUSBHostPipe *pipe = (__bridge IOUSBHostPipe *)ctx->pipeObject;
        NSMutableData *buffer = (__bridge NSMutableData *)ctx->bufferObject;

        MidiRunningStatus midiState = {0};
        uint32_t midiRateAccumulator = 0;

        while (!atomic_load(ctx->workerStop)) {
            uint64_t refillStartNs = monotonicNs();
            fillPlaybackFromRing(buffer.mutableBytes, ctx->ring);
            injectMidiOutIntoPlaybackBatch(buffer.mutableBytes,
                                           ctx->midiOutRing,
                                           &midiState,
                                           &midiRateAccumulator);
            uint64_t refillDoneNs = monotonicNs();

            if (refillDoneNs > refillStartNs)
                atomicUpdateMax(ctx->maxPlaybackRefillDelayNs,
                                refillDoneNs - refillStartNs);

            /*
             * A zero-byte synchronous transport failure may be transient.
             * Keep the already-consumed source audio in this USB buffer and
             * retry THIS SAME BLOCK once. Refilling here would silently skip
             * one block of music if the USB pipe recovered immediately.
             *
             * The Linux Jockey 3 driver likewise treats individual transport
             * errors as potentially transient. Its URBs are much shorter than
             * our 200 ms synchronous timeout, so v7.5 allows only one retry.
             */
            unsigned attempt = 0;
            BOOL delivered = NO;

            while (!atomic_load(ctx->workerStop) && !delivered) {
                attempt++;

                atomic_store(ctx->playbackPending, 1);

                NSError *ioError = nil;
                NSUInteger bytesTransferred = 0;
                uint64_t writeStartNs = monotonicNs();
                BOOL ok = [pipe sendIORequestWithData:buffer
                                      bytesTransferred:&bytesTransferred
                                    completionTimeout:0.200
                                                error:&ioError];
                uint64_t writeDoneNs = monotonicNs();

                atomic_store(ctx->playbackPending, 0);

                uint64_t writeDurationNs =
                    (writeDoneNs > writeStartNs) ? (writeDoneNs - writeStartNs) : 0;
                atomicUpdateMax(ctx->maxSyncWriteDurationNs, writeDurationNs);
                if (writeDurationNs > 10000000ULL)
                    atomic_fetch_add(ctx->syncWriteOver10ms, 1);
                if (writeDurationNs > 20000000ULL)
                    atomic_fetch_add(ctx->syncWriteOver20ms, 1);
                if (writeDurationNs > CATCHUP_TRIGGER_NS) {
                    atomic_fetch_add(ctx->syncWriteOver50ms, 1);
                    atomic_store(ctx->catchupRequested, true);
                }

                uint64_t completionNowNs = writeDoneNs;
                uint64_t previousCompletionNs =
                    atomic_exchange(ctx->lastPlaybackCompletionNs,
                                    completionNowNs);
                uint64_t completionGapNs = 0;

                if (previousCompletionNs != 0 &&
                    completionNowNs > previousCompletionNs) {
                    completionGapNs = completionNowNs - previousCompletionNs;
                    atomicUpdateMax(ctx->maxPlaybackCompletionGapNs,
                                    completionGapNs);
                    if (completionGapNs > 10000000ULL)
                        atomic_fetch_add(ctx->playbackGapOver10ms, 1);
                    if (completionGapNs > 50000000ULL)
                        atomic_fetch_add(ctx->playbackGapOver50ms, 1);
                }

                /*
                 * v8.0.7 diagnostic-only event snapshot.  Do no file I/O on
                 * the real-time thread.  For an operational write >20 ms,
                 * publish only atomics; the main thread prints the event later.
                 * The qualified transport/retry/catch-up decisions are unchanged.
                 */
                if (writeDurationNs > 20000000ULL &&
                    !atomic_load(ctx->workerStop)) {
                    uint64_t bhLastNs =
                        atomic_load_explicit(&ctx->ring->lastCallbackNs,
                                             memory_order_relaxed);
                    uint64_t captureLastNs =
                        atomic_load(ctx->lastCaptureSuccessNs);
                    uint64_t midiLastNs =
                        atomic_load(ctx->lastMidiSuccessNs);
                    uint64_t if0LastNs = atomic_load(ctx->if0ProbeLastNs);
                    uint64_t if1LastNs = atomic_load(ctx->if1ProbeLastNs);
                    uint64_t recoveryLastNs =
                        atomic_load(ctx->recoveryProbeLastNs);

                    atomic_store(ctx->lastSlowWriteEndNs, writeDoneNs);
                    atomic_store(ctx->lastSlowWriteDurationNs, writeDurationNs);
                    atomic_store(ctx->lastSlowWriteCompletionGapNs,
                                 completionGapNs);
                    atomic_store(ctx->lastSlowWriteRingDepthFrames,
                                 audioRingDepth(ctx->ring));
                    atomic_store(ctx->lastSlowWriteBytes,
                                 (unsigned long)bytesTransferred);
                    atomic_store(ctx->lastSlowWriteAttempt,
                                 (unsigned long)attempt);
                    atomic_store(ctx->lastSlowWriteSuccess,
                                 ok && bytesTransferred == BATCH_SIZE);
                    atomic_store(ctx->lastSlowWriteBhCallbackAgeNs,
                                 (bhLastNs != 0 && writeDoneNs > bhLastNs)
                                     ? writeDoneNs - bhLastNs : 0);
                    atomic_store(ctx->lastSlowWriteCaptureSuccessAgeNs,
                                 (captureLastNs != 0 && writeDoneNs > captureLastNs)
                                     ? writeDoneNs - captureLastNs : 0);
                    atomic_store(ctx->lastSlowWriteMidiSuccessAgeNs,
                                 (midiLastNs != 0 && writeDoneNs > midiLastNs)
                                     ? writeDoneNs - midiLastNs : 0);
                    atomic_store(ctx->lastSlowWriteIf0ProbeAgeNs,
                                 (if0LastNs != 0 && writeDoneNs > if0LastNs)
                                     ? writeDoneNs - if0LastNs : 0);
                    atomic_store(ctx->lastSlowWriteIf1ProbeAgeNs,
                                 (if1LastNs != 0 && writeDoneNs > if1LastNs)
                                     ? writeDoneNs - if1LastNs : 0);
                    atomic_store(ctx->lastSlowWriteRecoveryProbeAgeNs,
                                 (recoveryLastNs != 0 && writeDoneNs > recoveryLastNs)
                                     ? writeDoneNs - recoveryLastNs : 0);

                    Phase4PlaybackDiagEvent diagnosticEvent = {
                        .sequence = 0,
                        .eventEndNs = writeDoneNs,
                        .writeDurationNs = writeDurationNs,
                        .completionGapNs = completionGapNs,
                        .ringDepthFrames = audioRingDepth(ctx->ring),
                        .bytesTransferred = (unsigned long)bytesTransferred,
                        .attempt = (unsigned long)attempt,
                        .success = ok && bytesTransferred == BATCH_SIZE,
                        .bhCallbackAgeNs =
                            (bhLastNs != 0 && writeDoneNs > bhLastNs)
                                ? writeDoneNs - bhLastNs : 0,
                        .captureSuccessAgeNs =
                            (captureLastNs != 0 && writeDoneNs > captureLastNs)
                                ? writeDoneNs - captureLastNs : 0,
                        .midiSuccessAgeNs =
                            (midiLastNs != 0 && writeDoneNs > midiLastNs)
                                ? writeDoneNs - midiLastNs : 0,
                        .if0ProbeAgeNs =
                            (if0LastNs != 0 && writeDoneNs > if0LastNs)
                                ? writeDoneNs - if0LastNs : 0,
                        .if1ProbeAgeNs =
                            (if1LastNs != 0 && writeDoneNs > if1LastNs)
                                ? writeDoneNs - if1LastNs : 0,
                        .recoveryProbeAgeNs =
                            (recoveryLastNs != 0 && writeDoneNs > recoveryLastNs)
                                ? writeDoneNs - recoveryLastNs : 0
                    };
                    phase4PlaybackEventPush(&diagnosticEvent);

                    if (writeDurationNs > CATCHUP_TRIGGER_NS) {
                        atomic_fetch_add(ctx->slowWriteOperationalOver50ms, 1);
                        phase4PcmTriggerPush(
                            writeDoneNs,
                            writeDurationNs,
                            atomic_load_explicit(&gPhase4PcmRing.writeFrame,
                                                 memory_order_acquire));
                    }
                    /* Counter is retained for summary totals. */
                    atomic_fetch_add(ctx->slowWriteOperationalOver20ms, 1);
                }

                if (!ok || bytesTransferred != BATCH_SIZE) {
                    if (atomic_load(ctx->workerStop))
                        break;

                    atomic_fetch_add(ctx->playbackErrors, 1);
                    if (bytesTransferred != 0 &&
                        bytesTransferred != BATCH_SIZE) {
                        atomic_fetch_add(ctx->playbackPartialTransfers, 1);
                    }
                    if (ioError &&
                        [ioError.domain isEqualToString:IOUSBHostErrorDomain] &&
                        (IOReturn)ioError.code == kIOReturnTimeout) {
                        atomic_fetch_add(ctx->playbackTimeouts, 1);
                    } else {
                        atomic_fetch_add(ctx->playbackOtherErrors, 1);
                        atomic_store(ctx->playbackLastOtherStatus,
                                     ioError ? (int)ioError.code : 0);
                    }

                    fprintf(stderr,
                            "RT PLAYBACK ERROR: synchronous USB write failed "
                            "(%lu/%d bytes, attempt %u/2): %s\n",
                            (unsigned long)bytesTransferred,
                            BATCH_SIZE,
                            attempt,
                            ioError ? ioError.localizedDescription.UTF8String
                                    : "unknown error");

                    /*
                     * A partial transfer has ambiguous sample position. Never
                     * resend the whole block because that could duplicate audio.
                     */
                    if (bytesTransferred != 0 || attempt >= 2) {
                        fprintf(stderr,
                                "RT PLAYBACK FATAL: transport did not recover "
                                "after one same-block retry.\n");
                        atomic_store(ctx->playbackFatal, true);
                        break;
                    }

                    fprintf(stderr,
                            "RT PLAYBACK RETRY: zero-byte failure; retrying the "
                            "same 4096-byte audio block once.\n");
                    usleep(1000);
                    continue;
                }

                if (attempt > 1) {
                    fprintf(stderr,
                            "RT PLAYBACK RECOVERED: same-block retry succeeded "
                            "on attempt %u.\n",
                            attempt);
                }

                atomic_fetch_add(ctx->playbackTransfers, 1);
                atomic_store(ctx->lastPlaybackSuccessNs, completionNowNs);
                delivered = YES;

                /*
                 * v8.0 does NOT discard buffered audio after a late or
                 * transiently failed synchronous write. Catch-up handles the
                 * backlog after transport continuity is restored.
                 */
                (void)completionGapNs;
            }

            if (atomic_load(ctx->playbackFatal))
                break;
        }
    }

    return NULL;
}


typedef struct {
    void *pipeObject;
    void *bufferObject;
    atomic_bool *workerStop;
    atomic_ulong *captureTransfers;
    atomic_ulong *captureErrors;
    atomic_ulong *capturePending;
    atomic_uint_fast64_t *lastCaptureSuccessNs;
    atomic_uint_fast64_t *maxCaptureSyncDurationNs;
    atomic_ulong *captureSyncOver50ms;
    atomic_ulong *captureTimeouts;
    atomic_ulong *captureOtherErrors;
    atomic_int *captureLastOtherStatus;
    /* v8.0.7 diagnostic-only: operational slow-capture event snapshots. */
    atomic_ulong *captureOperationalOver20ms;
    atomic_ulong *captureOperationalOver50ms;
    atomic_uint_fast64_t *lastSlowCaptureEndNs;
    atomic_uint_fast64_t *lastSlowCaptureDurationNs;
    atomic_ulong *lastSlowCaptureBytes;
    atomic_bool *lastSlowCaptureSuccess;
    atomic_uint_fast64_t *lastSlowCapturePlaybackSuccessAgeNs;
    atomic_uint_fast64_t *lastSlowCaptureBhCallbackAgeNs;
    atomic_uint_fast64_t *lastSlowCaptureMidiSuccessAgeNs;
    atomic_uint_fast64_t *lastPlaybackSuccessNs;
    atomic_uint_fast64_t *lastMidiSuccessNs;
    AudioRing *ring;
    atomic_int *realtimePolicyResult;
} RealtimeCaptureContext;

static void *realtimeCaptureThreadMain(void *opaque)
{
    RealtimeCaptureContext *ctx = (RealtimeCaptureContext *)opaque;

    @autoreleasepool {
        pthread_setname_np("reloop.rt.capture");
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

        kern_return_t rt = makeCurrentThreadRealtime();
        atomic_store(ctx->realtimePolicyResult, (int)rt);

        IOUSBHostPipe *pipe = (__bridge IOUSBHostPipe *)ctx->pipeObject;
        NSMutableData *buffer = (__bridge NSMutableData *)ctx->bufferObject;

        while (!atomic_load(ctx->workerStop)) {
            NSError *ioError = nil;
            NSUInteger bytesTransferred = 0;
            atomic_store(ctx->capturePending, 1);

            uint64_t readStartNs = monotonicNs();
            BOOL ok = [pipe sendIORequestWithData:buffer
                                  bytesTransferred:&bytesTransferred
                                completionTimeout:0.200
                                            error:&ioError];
            uint64_t readDoneNs = monotonicNs();
            atomic_store(ctx->capturePending, 0);

            uint64_t durationNs =
                (readDoneNs > readStartNs) ? (readDoneNs - readStartNs) : 0;
            atomicUpdateMax(ctx->maxCaptureSyncDurationNs, durationNs);
            if (durationNs > 50000000ULL)
                atomic_fetch_add(ctx->captureSyncOver50ms, 1);

            if (durationNs > 20000000ULL &&
                !atomic_load(ctx->workerStop)) {
                atomic_store(ctx->lastSlowCaptureEndNs, readDoneNs);
                atomic_store(ctx->lastSlowCaptureDurationNs, durationNs);
                atomic_store(ctx->lastSlowCaptureBytes,
                             (unsigned long)bytesTransferred);
                atomic_store(ctx->lastSlowCaptureSuccess, ok);
                uint64_t playbackLastNs =
                    atomic_load(ctx->lastPlaybackSuccessNs);
                uint64_t midiLastNs = atomic_load(ctx->lastMidiSuccessNs);
                uint64_t bhLastNs =
                    atomic_load_explicit(&ctx->ring->lastCallbackNs,
                                         memory_order_relaxed);
                atomic_store(ctx->lastSlowCapturePlaybackSuccessAgeNs,
                             (playbackLastNs != 0 && readDoneNs > playbackLastNs)
                                 ? readDoneNs - playbackLastNs : 0);
                atomic_store(ctx->lastSlowCaptureMidiSuccessAgeNs,
                             (midiLastNs != 0 && readDoneNs > midiLastNs)
                                 ? readDoneNs - midiLastNs : 0);
                atomic_store(ctx->lastSlowCaptureBhCallbackAgeNs,
                             (bhLastNs != 0 && readDoneNs > bhLastNs)
                                 ? readDoneNs - bhLastNs : 0);
                Phase4CaptureDiagEvent diagnosticEvent = {
                    .sequence = 0,
                    .eventEndNs = readDoneNs,
                    .durationNs = durationNs,
                    .bytesTransferred = (unsigned long)bytesTransferred,
                    .success = ok,
                    .playbackSuccessAgeNs =
                        (playbackLastNs != 0 && readDoneNs > playbackLastNs)
                            ? readDoneNs - playbackLastNs : 0,
                    .bhCallbackAgeNs =
                        (bhLastNs != 0 && readDoneNs > bhLastNs)
                            ? readDoneNs - bhLastNs : 0,
                    .midiSuccessAgeNs =
                        (midiLastNs != 0 && readDoneNs > midiLastNs)
                            ? readDoneNs - midiLastNs : 0
                };
                phase4CaptureEventPush(&diagnosticEvent);
                if (durationNs > 50000000ULL)
                    atomic_fetch_add(ctx->captureOperationalOver50ms, 1);
                atomic_fetch_add(ctx->captureOperationalOver20ms, 1);
            }

            if (ok) {
                (void)bytesTransferred;
                atomic_fetch_add(ctx->captureTransfers, 1);
                atomic_store(ctx->lastCaptureSuccessNs, readDoneNs);
            } else if (!atomic_load(ctx->workerStop)) {
                atomic_fetch_add(ctx->captureErrors, 1);
                if (ioError &&
                    [ioError.domain isEqualToString:IOUSBHostErrorDomain] &&
                    (IOReturn)ioError.code == kIOReturnTimeout) {
                    atomic_fetch_add(ctx->captureTimeouts, 1);
                } else {
                    atomic_fetch_add(ctx->captureOtherErrors, 1);
                    atomic_store(ctx->captureLastOtherStatus,
                                 ioError ? (int)ioError.code : 0);
                }
                /* Avoid a tight loop if the endpoint is temporarily unhappy. */
                usleep(1000);
            }
        }
    }

    return NULL;
}

static AudioDeviceID findAudioDeviceByName(const char *wanted)
{
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 size = 0;
    OSStatus st =
        AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                       &addr,
                                       0,
                                       NULL,
                                       &size);

    if (st != noErr || size == 0)
        return kAudioObjectUnknown;

    UInt32 count = size / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(count, sizeof(AudioDeviceID));

    if (!devices)
        return kAudioObjectUnknown;

    st = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                    &addr,
                                    0,
                                    NULL,
                                    &size,
                                    devices);

    if (st != noErr) {
        free(devices);
        return kAudioObjectUnknown;
    }

    AudioDeviceID found = kAudioObjectUnknown;

    for (UInt32 i = 0; i < count; i++) {
        CFStringRef name = NULL;
        UInt32 nameSize = sizeof(name);

        AudioObjectPropertyAddress nameAddr = {
            kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        if (AudioObjectGetPropertyData(devices[i],
                                       &nameAddr,
                                       0,
                                       NULL,
                                       &nameSize,
                                       &name) == noErr &&
            name) {

            char buffer[256] = {0};

            if (CFStringGetCString(name,
                                   buffer,
                                   sizeof(buffer),
                                   kCFStringEncodingUTF8) &&
                strcmp(buffer, wanted) == 0) {
                found = devices[i];
                CFRelease(name);
                break;
            }

            CFRelease(name);
        }
    }

    free(devices);
    return found;
}


typedef struct {
    AudioObjectID clockSourceControl;
    AudioObjectID pitchControl;
    UInt32 originalClockSource;
    Float32 originalPitch;
    BOOL originalPitchValid;
    BOOL active;
    Float32 currentPitch;
} BlackHoleAdaptiveClock;

static AudioObjectID findControlByClass(AudioDeviceID device,
                                        AudioClassID wantedClass)
{
    AudioObjectPropertyAddress listAddr = {
        kAudioObjectPropertyControlList,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 size = 0;
    OSStatus st =
        AudioObjectGetPropertyDataSize(device,
                                       &listAddr,
                                       0,
                                       NULL,
                                       &size);

    if (st != noErr || size == 0)
        return kAudioObjectUnknown;

    UInt32 count = size / sizeof(AudioObjectID);
    AudioObjectID *controls = calloc(count, sizeof(AudioObjectID));

    if (!controls)
        return kAudioObjectUnknown;

    st = AudioObjectGetPropertyData(device,
                                    &listAddr,
                                    0,
                                    NULL,
                                    &size,
                                    controls);

    if (st != noErr) {
        free(controls);
        return kAudioObjectUnknown;
    }

    AudioObjectID found = kAudioObjectUnknown;

    for (UInt32 i = 0; i < count; i++) {
        AudioClassID classID = 0;
        UInt32 classSize = sizeof(classID);

        AudioObjectPropertyAddress classAddr = {
            kAudioObjectPropertyClass,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        if (AudioObjectGetPropertyData(controls[i],
                                       &classAddr,
                                       0,
                                       NULL,
                                       &classSize,
                                       &classID) == noErr &&
            classID == wantedClass) {
            found = controls[i];
            break;
        }
    }

    free(controls);
    return found;
}

static BOOL readUInt32Control(AudioObjectID control,
                              AudioObjectPropertySelector selector,
                              UInt32 *value)
{
    if (control == kAudioObjectUnknown || !value)
        return NO;

    AudioObjectPropertyAddress addr = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 size = sizeof(*value);
    return AudioObjectGetPropertyData(control,
                                      &addr,
                                      0,
                                      NULL,
                                      &size,
                                      value) == noErr;
}

static BOOL writeUInt32Control(AudioObjectID control,
                               AudioObjectPropertySelector selector,
                               UInt32 value)
{
    if (control == kAudioObjectUnknown)
        return NO;

    AudioObjectPropertyAddress addr = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    return AudioObjectSetPropertyData(control,
                                      &addr,
                                      0,
                                      NULL,
                                      sizeof(value),
                                      &value) == noErr;
}

static BOOL readFloatControl(AudioObjectID control,
                             AudioObjectPropertySelector selector,
                             Float32 *value)
{
    if (control == kAudioObjectUnknown || !value)
        return NO;

    AudioObjectPropertyAddress addr = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 size = sizeof(*value);
    return AudioObjectGetPropertyData(control,
                                      &addr,
                                      0,
                                      NULL,
                                      &size,
                                      value) == noErr;
}

static BOOL writeFloatControl(AudioObjectID control,
                              AudioObjectPropertySelector selector,
                              Float32 value)
{
    if (control == kAudioObjectUnknown)
        return NO;

    AudioObjectPropertyAddress addr = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    return AudioObjectSetPropertyData(control,
                                      &addr,
                                      0,
                                      NULL,
                                      sizeof(value),
                                      &value) == noErr;
}

static BOOL setBlackHolePitch(BlackHoleAdaptiveClock *clock,
                              Float32 requestedPitch)
{
    if (!clock || clock->pitchControl == kAudioObjectUnknown)
        return NO;

    if (requestedPitch < 0.0f)
        requestedPitch = 0.0f;
    if (requestedPitch > 1.0f)
        requestedPitch = 1.0f;

    if (!writeFloatControl(clock->pitchControl,
                           kAudioStereoPanControlPropertyValue,
                           requestedPitch))
        return NO;

    Float32 actualPitch = 0.0f;
    if (!readFloatControl(clock->pitchControl,
                          kAudioStereoPanControlPropertyValue,
                          &actualPitch))
        return NO;

    clock->currentPitch = actualPitch;
    return fabsf(actualPitch - requestedPitch) < 0.00001f;
}

static BOOL setupBlackHoleAdaptiveClock(AudioDeviceID device,
                                        BlackHoleAdaptiveClock *clock)
{
    if (!clock)
        return NO;

    memset(clock, 0, sizeof(*clock));
    clock->clockSourceControl = kAudioObjectUnknown;
    clock->pitchControl = kAudioObjectUnknown;
    clock->originalPitch = 0.5f;
    clock->currentPitch = 0.5f;

    clock->clockSourceControl =
        findControlByClass(device, kAudioClockSourceControlClassID);

    if (clock->clockSourceControl == kAudioObjectUnknown) {
        fprintf(stderr,
                "ERROR: BlackHole adjustable clock-source control not found.\n");
        return NO;
    }

    if (!readUInt32Control(clock->clockSourceControl,
                           kAudioSelectorControlPropertyCurrentItem,
                           &clock->originalClockSource)) {
        fprintf(stderr,
                "ERROR: could not read BlackHole clock source.\n");
        return NO;
    }

    if (clock->originalClockSource == 1) {
        clock->pitchControl =
            findControlByClass(device, kAudioStereoPanControlClassID);

        if (clock->pitchControl != kAudioObjectUnknown &&
            readFloatControl(clock->pitchControl,
                             kAudioStereoPanControlPropertyValue,
                             &clock->originalPitch)) {
            clock->originalPitchValid = YES;
        }
    }

    if (clock->originalClockSource != 1) {
        if (!writeUInt32Control(clock->clockSourceControl,
                                kAudioSelectorControlPropertyCurrentItem,
                                1)) {
            fprintf(stderr,
                    "ERROR: could not enable BlackHole Internal Adjustable clock.\n");
            return NO;
        }
    }

    /*
     * Enabling the adjustable source is a HAL configuration change.
     * BlackHole exposes its pitch control only after that change completes.
     */
    for (int i = 0; i < 200; i++) {
        UInt32 source = 0;

        if (readUInt32Control(clock->clockSourceControl,
                              kAudioSelectorControlPropertyCurrentItem,
                              &source) &&
            source == 1) {
            clock->pitchControl =
                findControlByClass(device, kAudioStereoPanControlClassID);

            if (clock->pitchControl != kAudioObjectUnknown)
                break;
        }

        usleep(10000);
    }

    if (clock->pitchControl == kAudioObjectUnknown) {
        fprintf(stderr,
                "ERROR: BlackHole pitch control did not appear after enabling "
                "Internal Adjustable.\n");

        if (clock->originalClockSource != 1)
            writeUInt32Control(clock->clockSourceControl,
                               kAudioSelectorControlPropertyCurrentItem,
                               clock->originalClockSource);
        return NO;
    }

    if (clock->originalClockSource == 1 && !clock->originalPitchValid) {
        if (readFloatControl(clock->pitchControl,
                             kAudioStereoPanControlPropertyValue,
                             &clock->originalPitch))
            clock->originalPitchValid = YES;
    }

    /*
     * Start from nominal speed. The servo measures the actual clock mismatch
     * and then moves only as far as needed.
     */
    if (!setBlackHolePitch(clock, 0.5f)) {
        fprintf(stderr,
                "ERROR: could not initialize BlackHole pitch to nominal.\n");
        return NO;
    }

    clock->active = YES;

    printf("BlackHole adaptive clock enabled: Internal Adjustable, "
           "starting balance %.6f.\n",
           clock->currentPitch);
    return YES;
}

static void restoreBlackHoleClock(BlackHoleAdaptiveClock *clock)
{
    if (!clock || !clock->active)
        return;

    if (clock->originalClockSource == 1 && clock->originalPitchValid) {
        setBlackHolePitch(clock, clock->originalPitch);
    } else {
        setBlackHolePitch(clock, 0.5f);
    }

    if (clock->originalClockSource != 1) {
        writeUInt32Control(clock->clockSourceControl,
                           kAudioSelectorControlPropertyCurrentItem,
                           clock->originalClockSource);
    }

    clock->active = NO;
}

static double clampDouble(double value, double lo, double hi)
{
    if (value < lo)
        return lo;
    if (value > hi)
        return hi;
    return value;
}

static double pitchToPpm(Float32 pitch)
{
    return ((double)pitch - 0.5) * 20000.0;
}

static Float32 ppmToPitch(double ppm)
{
    return (Float32)(0.5 + ppm / 20000.0);
}

static BOOL configureBlackHole(AudioDeviceID device)
{
    Float64 wantedRate = 48000.0;

    AudioObjectPropertyAddress rateAddr = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    Boolean rateIsSettable = false;
    OSStatus settableStatus =
        AudioObjectIsPropertySettable(device,
                                      &rateAddr,
                                      &rateIsSettable);

    if (settableStatus != noErr) {
        fprintf(stderr,
                "ERROR checking whether BlackHole sample rate is settable "
                "(OSStatus %d).\n",
                (int)settableStatus);
        return NO;
    }

    if (rateIsSettable) {
        UInt32 size = sizeof(wantedRate);
        OSStatus st =
            AudioObjectSetPropertyData(device,
                                       &rateAddr,
                                       0,
                                       NULL,
                                       size,
                                       &wantedRate);

        if (st != noErr) {
            fprintf(stderr,
                    "ERROR setting BlackHole to 48 kHz (OSStatus %d).\n",
                    (int)st);
            return NO;
        }
    }

    Float64 actualRate = 0.0;
    UInt32 rateSize = sizeof(actualRate);

    OSStatus st =
        AudioObjectGetPropertyData(device,
                                   &rateAddr,
                                   0,
                                   NULL,
                                   &rateSize,
                                   &actualRate);

    if (st != noErr || actualRate < 47999.0 || actualRate > 48001.0) {
        fprintf(stderr,
                "ERROR: BlackHole nominal rate is %.1f Hz, expected 48000.\n",
                actualRate);
        return NO;
    }

    AudioObjectPropertyAddress cfgAddr = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };

    UInt32 cfgSize = 0;
    st = AudioObjectGetPropertyDataSize(device,
                                        &cfgAddr,
                                        0,
                                        NULL,
                                        &cfgSize);

    if (st != noErr || cfgSize == 0) {
        fprintf(stderr,
                "ERROR reading BlackHole input stream configuration.\n");
        return NO;
    }

    AudioBufferList *cfg = malloc(cfgSize);
    if (!cfg)
        return NO;

    st = AudioObjectGetPropertyData(device,
                                    &cfgAddr,
                                    0,
                                    NULL,
                                    &cfgSize,
                                    cfg);

    UInt32 channels = 0;

    if (st == noErr) {
        for (UInt32 i = 0; i < cfg->mNumberBuffers; i++)
            channels += cfg->mBuffers[i].mNumberChannels;
    }

    free(cfg);

    if (st != noErr || channels < 4) {
        fprintf(stderr,
                "ERROR: BlackHole input has %u channels; need at least 4.\n",
                channels);
        return NO;
    }

    printf("BlackHole 16ch ready: %.0f Hz, %u input channels.\n",
           actualRate, channels);
    return YES;
}


int main(void)
{
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN); /* survive tee exiting during terminal interrupts */
        signal(SIGINT, handleSignal);
        signal(SIGTERM, handleSignal);
        signal(SIGUSR1, handlePhase4ManualPcmSignal);

        printf("Reloop Jockey 3 ME audio + CoreMIDI bridge v8.0.7 (v8.0.4 behavior + diagnostic-only USB/MIDI event logging)\n");
        printf("48 kHz, vendor-trace init + direct completion-driven async USB streaming.\n");
        printf("Firmware is NOT modified by this program.\n");
        printf("BlackHole channels 1/2 -> Reloop Master L/R\n");
        printf("BlackHole channels 4/3 -> Reloop Headphones L/R (verified in Traktor pan test)\n");
        printf("Press Control-C to stop cleanly.\n");
        printf("Phase 4: SIGUSR1 requests one manual 5 s pre + 5 s post PCM snapshot.\n\n");

        AudioDeviceID blackHole = findAudioDeviceByName(BLACKHOLE_NAME);

        if (blackHole == kAudioObjectUnknown) {
            fprintf(stderr,
                    "ERROR: Core Audio device \"%s\" was not found.\n",
                    BLACKHOLE_NAME);
            return 1;
        }

        if (!configureBlackHole(blackHole))
            return 2;

        BlackHoleAdaptiveClock adaptiveClock;
        if (!setupBlackHoleAdaptiveClock(blackHole, &adaptiveClock))
            return 2;

        AudioRing *ring = calloc(1, sizeof(AudioRing));
        if (!ring) {
            fprintf(stderr, "ERROR allocating AudioRing state.\n");
            restoreBlackHoleClock(&adaptiveClock);
            return 3;
        }

        if (!audioRingInit(ring)) {
            fprintf(stderr, "ERROR allocating audio ring buffer.\n");
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 3;
        }

        AudioDeviceIOProcID ioProcID = NULL;

        OSStatus ast =
            AudioDeviceCreateIOProcID(blackHole,
                                      blackHoleIOProc,
                                      ring,
                                      &ioProcID);

        if (ast != noErr || !ioProcID) {
            fprintf(stderr,
                    "ERROR creating BlackHole IOProc (OSStatus %d).\n",
                    (int)ast);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 4;
        }

        /*
         * Cold-boot timing: current Linux v4 deliberately waits before the
         * first control transfer.  Keep the same conservative behavior here.
         */
        usleep(300000);

        if (!setConfig1WithRetry()) {
            fprintf(stderr,
                    "ERROR: could not configure the Reloop after retries.\n");
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 5;
        }

        printf("USB configuration 1 selected.\n");

        /*
         * IOUSBHost services asynchronous I/O on the queue supplied when the
         * interface object is created.  Use dedicated user-interactive serial
         * queues instead of IOUSBHost's default queue so playback completion
         * delivery cannot be deprioritized behind unrelated work.
         */
        dispatch_queue_attr_t usbServiceQueueAttr =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                    QOS_CLASS_USER_INTERACTIVE,
                                                    0);

        dispatch_queue_t usbIf0ServiceQueue =
            dispatch_queue_create("reloop.usb.if0.service",
                                  usbServiceQueueAttr);
        dispatch_queue_t usbIf1ServiceQueue =
            dispatch_queue_create("reloop.usb.if1.service",
                                  usbServiceQueueAttr);

        IOUSBHostInterface *if0 =
            openInterfaceWithRetry(0, usbIf0ServiceQueue);
        IOUSBHostInterface *if1 =
            openInterfaceWithRetry(1, usbIf1ServiceQueue);

        if (!if0 || !if1) {
            fprintf(stderr,
                    "ERROR: USB interfaces did not appear after configuration.\n");
            if (if1) [if1 destroy];
            if (if0) [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 6;
        }

        printf("USB interfaces 0 and 1 opened on dedicated user-interactive service queues.\n");

        IOUSBHostPipe *pipe05 = nil;
        IOUSBHostPipe *pipe83 = nil;
        IOUSBHostPipe *pipe86 = nil;
        NSError *error = nil;

        /*
         * Ploytec protocol initialization below deliberately follows the
         * September 2026 Linux v4 driver's vendor-trace-derived ordering.
         *
         * PASS 1: initialize the device itself.
         * The firmware read MUST precede SET_INTERFACE.  Vendor traces do this
         * first, and Linux v4 treats that read as load-bearing because changing
         * alt settings after EP0 has gone silent can leave endpoints disabled.
         */
        printf("Vendor protocol pass 1: firmware -> alt1 -> clear halts -> status -> start.\n");

        if (!readFirmware(if0, &error)) {
            fprintf(stderr, "ERROR reading firmware before first alt-setting change: %s\n",
                    error ? error.localizedDescription.UTF8String
                          : "unknown error");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 7;
        }

        if (!selectAlt1AndClear(if0, if1,
                                &pipe05, &pipe83, &pipe86)) {
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 8;
        }

        uint8_t initStatus = 0;
        error = nil;

        /*
         * ploytec_initialize_device() ends with a status read.
         */
        if (!getStatus(if0, &initStatus, &error)) {
            fprintf(stderr, "ERROR reading status after first vendor init pass.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 9;
        }

        /*
         * ploytec_start_streaming(): read status AGAIN, then write it back
         * with bit 0x20 set.  The write is unconditional even if 0x20 was
         * already reported; vendor traces and Linux v4 show that the write has
         * restart semantics beyond merely changing the bit.
         */
        uint8_t startStatus = 0;
        error = nil;

        if (!getStatus(if0, &startStatus, &error) ||
            !setStatus(if0, startStatus | 0x20, &error)) {
            fprintf(stderr, "ERROR starting streaming after first vendor init pass.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 10;
        }

        /*
         * PASS 2: jockey3_set_rate(..., cold_init=true) starts by running
         * ploytec_initialize_device() again.  Preserve that apparently
         * redundant vendor sequence instead of "optimizing" it away.
         */
        printf("Vendor protocol pass 2: reinitialize before programming 48 kHz.\n");

        error = nil;
        if (!readFirmware(if0, &error)) {
            fprintf(stderr, "ERROR reading firmware before rate-programming init pass: %s\n",
                    error ? error.localizedDescription.UTF8String
                          : "unknown error");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 11;
        }

        if (!selectAlt1AndClear(if0, if1,
                                &pipe05, &pipe83, &pipe86)) {
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 12;
        }

        uint8_t rateInitStatus = 0;
        error = nil;

        if (!getStatus(if0, &rateInitStatus, &error)) {
            fprintf(stderr, "ERROR reading status before rate programming.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 13;
        }

        uint32_t currentRate = 0;
        error = nil;

        if (!getRate(if0, 0x0000, &currentRate, &error)) {
            fprintf(stderr, "ERROR reading device-wide Reloop hardware rate.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 14;
        }

        printf("Current Reloop hardware rate: %u Hz\n", currentRate);

        /*
         * Exact cold-init rate shape from the current vendor-trace-derived
         * Linux v4 protocol layer:
         *   quiet 14-15 ms
         *   write 86,05,86,05,86
         *   verify at 86
         *   quiet 50-51 ms
         *   unconditional start-streaming status write
         */
        usleep(14500);

        const uint16_t burst[] = {
            0x0086, 0x0005, 0x0086, 0x0005, 0x0086
        };

        for (int i = 0; i < 5; i++) {
            error = nil;

            if (!writeRate(if0, burst[i], 48000, &error)) {
                fprintf(stderr,
                        "ERROR programming Reloop 48 kHz at vendor burst step %d.\n",
                        i + 1);
                [if1 destroy];
                [if0 destroy];
                AudioDeviceDestroyIOProcID(blackHole, ioProcID);
                audioRingDestroy(ring);
                free(ring);
                restoreBlackHoleClock(&adaptiveClock);
                return 15;
            }
        }

        uint32_t verifiedRate = 0;
        error = nil;

        if (!getRate(if0, 0x0086, &verifiedRate, &error) ||
            verifiedRate != 48000) {
            fprintf(stderr, "ERROR verifying Reloop 48 kHz at endpoint 0x86.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 16;
        }

        usleep(50500);

        uint8_t finalStartStatus = 0;
        error = nil;

        if (!getStatus(if0, &finalStartStatus, &error) ||
            !setStatus(if0, finalStartStatus | 0x20, &error)) {
            fprintf(stderr,
                    "ERROR issuing unconditional vendor final streaming start.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 17;
        }

        printf("Vendor-derived Ploytec initialization complete at 48000 Hz.\n");

        /*
         * Eight independent playback buffers keep the bulk OUT endpoint
         * continuously queued.  v1 used one synchronous request, so every
         * completion had an encode/refill/submit gap.
         */
        NSMutableArray<NSMutableData *> *playbackBuffers =
            [NSMutableArray arrayWithCapacity:PLAYBACK_URB_COUNT];

        for (NSUInteger i = 0; i < PLAYBACK_URB_COUNT; i++) {
            NSMutableData *buffer =
                [if0 ioDataWithCapacity:BATCH_SIZE error:&error];

            if (!buffer) {
                fprintf(stderr,
                        "ERROR allocating playback USB buffer %lu.\n",
                        (unsigned long)i);
                [if1 destroy];
                [if0 destroy];
                AudioDeviceDestroyIOProcID(blackHole, ioProcID);
                audioRingDestroy(ring);
                free(ring);
                restoreBlackHoleClock(&adaptiveClock);
            return 22;
            }

            [playbackBuffers addObject:buffer];
        }

        /*
         * v5 steady-state architecture:
         * - playback: 8 asynchronous requests, refilled and resubmitted directly
         *   from the IOUSBHost completion path;
         * - capture: 8 asynchronous requests, immediately resubmitted;
         * - MIDI IN: one continuously queued asynchronous request.
         *
         * This removes the v4 playback semaphore/worker hand-off and the
         * synchronous capture/MIDI drain loops.  The current Linux Jockey 3
         * driver uses the same core rule: completed requests are resubmitted
         * directly from their completion path so the endpoint stays fed.
         */
        NSMutableArray<NSMutableData *> *captureBuffers =
            [NSMutableArray arrayWithCapacity:PLAYBACK_URB_COUNT];

        for (NSUInteger i = 0; i < PLAYBACK_URB_COUNT; i++) {
            NSMutableData *buffer =
                [if1 ioDataWithCapacity:BATCH_SIZE error:&error];

            if (!buffer) {
                fprintf(stderr,
                        "ERROR allocating capture USB buffer %lu.\n",
                        (unsigned long)i);
                [if1 destroy];
                [if0 destroy];
                AudioDeviceDestroyIOProcID(blackHole, ioProcID);
                audioRingDestroy(ring);
                free(ring);
                restoreBlackHoleClock(&adaptiveClock);
                return 21;
            }

            [captureBuffers addObject:buffer];
        }

        NSMutableData *midi =
            [if0 ioDataWithCapacity:PLOYTEC_PKT_SIZE error:&error];

        if (!midi) {
            fprintf(stderr, "ERROR allocating MIDI drain buffer.\n");
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 21;
        }

        __block atomic_bool workerStop;
        __block atomic_bool playbackFatal;
        __block atomic_ulong playbackTransfers;
        __block atomic_ulong playbackErrors;
        __block atomic_ulong playbackPending;
        __block atomic_uint_fast64_t lastPlaybackCompletionNs;
        __block atomic_uint_fast64_t lastPlaybackSuccessNs;
        __block atomic_uint_fast64_t maxPlaybackCompletionGapNs;
        __block atomic_uint_fast64_t playbackGapOver10ms;
        __block atomic_uint_fast64_t playbackGapOver50ms;
        __block atomic_uint_fast64_t maxPlaybackRefillDelayNs;
        __block atomic_uint_fast64_t maxSyncWriteDurationNs;
        __block atomic_ulong syncWriteOver10ms;
        __block atomic_ulong syncWriteOver20ms;
        __block atomic_ulong syncWriteOver50ms;
        __block atomic_ulong playbackTimeouts;
        __block atomic_ulong playbackOtherErrors;
        __block atomic_ulong playbackPartialTransfers;
        __block atomic_int playbackLastOtherStatus;
        __block atomic_ulong slowWriteOperationalOver20ms;
        __block atomic_ulong slowWriteOperationalOver50ms;
        __block atomic_uint_fast64_t lastSlowWriteEndNs;
        __block atomic_uint_fast64_t lastSlowWriteDurationNs;
        __block atomic_uint_fast64_t lastSlowWriteCompletionGapNs;
        __block atomic_uint_fast64_t lastSlowWriteRingDepthFrames;
        __block atomic_ulong lastSlowWriteBytes;
        __block atomic_ulong lastSlowWriteAttempt;
        __block atomic_bool lastSlowWriteSuccess;
        __block atomic_uint_fast64_t lastSlowWriteBhCallbackAgeNs;
        __block atomic_uint_fast64_t lastSlowWriteCaptureSuccessAgeNs;
        __block atomic_uint_fast64_t lastSlowWriteMidiSuccessAgeNs;
        __block atomic_uint_fast64_t lastSlowWriteIf0ProbeAgeNs;
        __block atomic_uint_fast64_t lastSlowWriteIf1ProbeAgeNs;
        __block atomic_uint_fast64_t lastSlowWriteRecoveryProbeAgeNs;
        __block atomic_ulong softResyncCount;
        __block atomic_uint_fast64_t softResyncFramesDiscarded;
        __block atomic_bool catchupRequested;
        __block atomic_ulong captureTransfers;
        __block atomic_ulong captureErrors;
        __block atomic_ulong capturePending;
        __block atomic_uint_fast64_t maxCaptureSyncDurationNs;
        __block atomic_ulong captureSyncOver50ms;
        __block atomic_ulong captureTimeouts;
        __block atomic_ulong captureOtherErrors;
        __block atomic_int captureLastOtherStatus;
        __block atomic_ulong captureOperationalOver20ms;
        __block atomic_ulong captureOperationalOver50ms;
        __block atomic_uint_fast64_t lastSlowCaptureEndNs;
        __block atomic_uint_fast64_t lastSlowCaptureDurationNs;
        __block atomic_ulong lastSlowCaptureBytes;
        __block atomic_bool lastSlowCaptureSuccess;
        __block atomic_uint_fast64_t lastSlowCapturePlaybackSuccessAgeNs;
        __block atomic_uint_fast64_t lastSlowCaptureBhCallbackAgeNs;
        __block atomic_uint_fast64_t lastSlowCaptureMidiSuccessAgeNs;
        __block atomic_ulong midiDrainTransfers;
        __block atomic_ulong midiDrainErrors;
        __block atomic_ulong midiDrainTimeouts;
        __block atomic_ulong midiDrainOtherErrors;
        __block atomic_ulong midiQueueFailures;
        __block atomic_int midiLastOtherStatus;
        __block atomic_uint_fast64_t midiLastOtherErrorNs;
        __block atomic_ulong midiPending;
        __block atomic_uint_fast64_t lastCaptureSuccessNs;
        __block atomic_uint_fast64_t lastMidiSuccessNs;
        __block atomic_bool suppressResubmit;
        __block atomic_bool recoveryInProgress;
        __block atomic_bool recoveryMonitoring;
        __block atomic_uint_fast64_t recoveryFirstPlaybackNs;
        __block atomic_uint_fast64_t recoveryLastPlaybackNs;
        __block atomic_ulong recoveryPlaybackCompletions;
        __block atomic_ulong warmRecoveryAttempts;
        __block atomic_ulong warmRecoverySuccesses;
        __block atomic_ulong warmRecoveryFailures;
        __block atomic_uint_fast64_t maxWarmRecoveryNs;
        /* v6.3 diagnostic probes: measure dispatch/service-queue scheduling itself. */
        __block atomic_uint_fast64_t if0ProbeLastNs;
        __block atomic_uint_fast64_t if0ProbeMaxGapNs;
        __block atomic_ulong if0ProbeOver20ms;
        __block atomic_ulong if0ProbeOver50ms;
        __block atomic_uint_fast64_t if1ProbeLastNs;
        __block atomic_uint_fast64_t if1ProbeMaxGapNs;
        __block atomic_ulong if1ProbeOver20ms;
        __block atomic_ulong if1ProbeOver50ms;
        __block atomic_uint_fast64_t recoveryProbeLastNs;
        __block atomic_uint_fast64_t recoveryProbeMaxGapNs;
        __block atomic_ulong recoveryProbeOver20ms;
        __block atomic_ulong recoveryProbeOver50ms;

        atomic_init(&workerStop, false);
        atomic_init(&playbackFatal, false);
        atomic_init(&playbackTransfers, 0);
        atomic_init(&playbackErrors, 0);
        atomic_init(&playbackPending, 0);
        atomic_init(&lastPlaybackCompletionNs, 0);
        atomic_init(&lastPlaybackSuccessNs, 0);
        atomic_init(&maxPlaybackCompletionGapNs, 0);
        atomic_init(&playbackGapOver10ms, 0);
        atomic_init(&playbackGapOver50ms, 0);
        atomic_init(&maxPlaybackRefillDelayNs, 0);
        atomic_init(&maxSyncWriteDurationNs, 0);
        atomic_init(&syncWriteOver10ms, 0);
        atomic_init(&syncWriteOver20ms, 0);
        atomic_init(&syncWriteOver50ms, 0);
        atomic_init(&playbackTimeouts, 0);
        atomic_init(&playbackOtherErrors, 0);
        atomic_init(&playbackPartialTransfers, 0);
        atomic_init(&playbackLastOtherStatus, 0);
        atomic_init(&slowWriteOperationalOver20ms, 0);
        atomic_init(&slowWriteOperationalOver50ms, 0);
        atomic_init(&lastSlowWriteEndNs, 0);
        atomic_init(&lastSlowWriteDurationNs, 0);
        atomic_init(&lastSlowWriteCompletionGapNs, 0);
        atomic_init(&lastSlowWriteRingDepthFrames, 0);
        atomic_init(&lastSlowWriteBytes, 0);
        atomic_init(&lastSlowWriteAttempt, 0);
        atomic_init(&lastSlowWriteSuccess, false);
        atomic_init(&lastSlowWriteBhCallbackAgeNs, 0);
        atomic_init(&lastSlowWriteCaptureSuccessAgeNs, 0);
        atomic_init(&lastSlowWriteMidiSuccessAgeNs, 0);
        atomic_init(&lastSlowWriteIf0ProbeAgeNs, 0);
        atomic_init(&lastSlowWriteIf1ProbeAgeNs, 0);
        atomic_init(&lastSlowWriteRecoveryProbeAgeNs, 0);
        atomic_init(&softResyncCount, 0);
        atomic_init(&softResyncFramesDiscarded, 0);
        atomic_init(&catchupRequested, false);
        atomic_init(&captureTransfers, 0);
        atomic_init(&captureErrors, 0);
        atomic_init(&capturePending, 0);
        atomic_init(&maxCaptureSyncDurationNs, 0);
        atomic_init(&captureSyncOver50ms, 0);
        atomic_init(&captureTimeouts, 0);
        atomic_init(&captureOtherErrors, 0);
        atomic_init(&captureLastOtherStatus, 0);
        atomic_init(&captureOperationalOver20ms, 0);
        atomic_init(&captureOperationalOver50ms, 0);
        atomic_init(&lastSlowCaptureEndNs, 0);
        atomic_init(&lastSlowCaptureDurationNs, 0);
        atomic_init(&lastSlowCaptureBytes, 0);
        atomic_init(&lastSlowCaptureSuccess, false);
        atomic_init(&lastSlowCapturePlaybackSuccessAgeNs, 0);
        atomic_init(&lastSlowCaptureBhCallbackAgeNs, 0);
        atomic_init(&lastSlowCaptureMidiSuccessAgeNs, 0);
        atomic_init(&midiDrainTransfers, 0);
        atomic_init(&midiDrainErrors, 0);
        atomic_init(&midiDrainTimeouts, 0);
        atomic_init(&midiDrainOtherErrors, 0);
        atomic_init(&midiQueueFailures, 0);
        atomic_init(&midiLastOtherStatus, 0);
        atomic_init(&midiLastOtherErrorNs, 0);
        atomic_init(&midiPending, 0);
        atomic_init(&lastCaptureSuccessNs, 0);
        atomic_init(&lastMidiSuccessNs, 0);
        atomic_init(&suppressResubmit, false);
        atomic_init(&recoveryInProgress, false);
        atomic_init(&recoveryMonitoring, false);
        atomic_init(&recoveryFirstPlaybackNs, 0);
        atomic_init(&recoveryLastPlaybackNs, 0);
        atomic_init(&recoveryPlaybackCompletions, 0);
        atomic_init(&warmRecoveryAttempts, 0);
        atomic_init(&warmRecoverySuccesses, 0);
        atomic_init(&warmRecoveryFailures, 0);
        atomic_init(&maxWarmRecoveryNs, 0);
        atomic_init(&if0ProbeLastNs, 0);
        atomic_init(&if0ProbeMaxGapNs, 0);
        atomic_init(&if0ProbeOver20ms, 0);
        atomic_init(&if0ProbeOver50ms, 0);
        atomic_init(&if1ProbeLastNs, 0);
        atomic_init(&if1ProbeMaxGapNs, 0);
        atomic_init(&if1ProbeOver20ms, 0);
        atomic_init(&if1ProbeOver50ms, 0);
        atomic_init(&recoveryProbeLastNs, 0);
        atomic_init(&recoveryProbeMaxGapNs, 0);
        atomic_init(&recoveryProbeOver20ms, 0);
        atomic_init(&recoveryProbeOver50ms, 0);

        /* Allocate/touch the static diagnostic PCM pages before RT work. */
        phase4PcmInit();
        phase4EventRingsInit();

        MidiOutRing midiOutRing;
        midiOutRingInit(&midiOutRing);

        CoreMidiBridge coreMidiBridge;
        memset(&coreMidiBridge, 0, sizeof(coreMidiBridge));
        CoreMidiBridge *coreMidi = &coreMidiBridge;

        /*
         * Recursive block variables let each completion immediately queue its
         * own next transfer.  IOUSBHost delivers interface completions on the
         * dedicated serial service queues created above, so playback remains a
         * single consumer of AudioRing and preserves sample order.
         */
        __block __weak BOOL (^weakEnqueuePlayback)(NSUInteger) = nil;
        __block __weak BOOL (^weakEnqueueCapture)(NSUInteger) = nil;
        __block __weak BOOL (^weakEnqueueMidi)(void) = nil;

        __attribute__((objc_precise_lifetime))
        BOOL (^enqueuePlayback)(NSUInteger) = ^BOOL(NSUInteger idx) {
            NSError *queueError = nil;

            atomic_fetch_add(&playbackPending, 1);

            BOOL queued =
                [pipe05 enqueueIORequestWithData:playbackBuffers[idx]
                              completionTimeout:1.0
                                          error:&queueError
                              completionHandler:
                    ^(IOReturn completionStatus,
                      NSUInteger bytesTransferred) {
                        atomic_fetch_sub(&playbackPending, 1);

                        uint64_t completionNowNs = monotonicNs();
                        uint64_t previousCompletionNs =
                            atomic_exchange(&lastPlaybackCompletionNs,
                                            completionNowNs);
                        uint64_t completionGapNs = 0;

                        if (previousCompletionNs != 0 &&
                            completionNowNs > previousCompletionNs) {
                            completionGapNs =
                                completionNowNs - previousCompletionNs;

                            atomicUpdateMax(&maxPlaybackCompletionGapNs,
                                            completionGapNs);

                            if (completionGapNs > 10000000ULL)
                                atomic_fetch_add(&playbackGapOver10ms, 1);

                            if (completionGapNs > 50000000ULL)
                                atomic_fetch_add(&playbackGapOver50ms, 1);
                        }

                        if (completionStatus == kIOReturnSuccess &&
                            bytesTransferred == BATCH_SIZE) {
                            atomic_fetch_add(&playbackTransfers, 1);
                            atomic_store(&lastPlaybackSuccessNs,
                                         completionNowNs);

                            if (atomic_load(&recoveryMonitoring)) {
                                uint64_t expectedFirst = 0;
                                atomic_compare_exchange_strong(
                                    &recoveryFirstPlaybackNs,
                                    &expectedFirst,
                                    completionNowNs);
                                atomic_store(&recoveryLastPlaybackNs,
                                             completionNowNs);
                                atomic_fetch_add(&recoveryPlaybackCompletions, 1);
                            }
                        } else if (!atomic_load(&workerStop) &&
                                   !atomic_load(&suppressResubmit)) {
                            atomic_fetch_add(&playbackErrors, 1);
                        }

                        if (atomic_load(&workerStop) ||
                            atomic_load(&suppressResubmit))
                            return;

                        /*
                         * Userspace debounce: if playback was late but recovered
                         * before the hard watchdog fired, do not tear down USB.
                         * We are already on interface 0's serial service queue,
                         * which is the sole AudioRing consumer, so it is safe to
                         * discard the stale backlog here before refilling the
                         * completed request.  This is the cheap path for transient
                         * macOS/IOUSBHost callback delays.
                         */
                        if (completionStatus == kIOReturnSuccess &&
                            bytesTransferred == BATCH_SIZE &&
                            completionGapNs >= SOFT_RESYNC_GAP_NS &&
                            !atomic_load(&recoveryInProgress)) {
                            uint64_t discarded =
                                audioRingTrimOldestToDepth(ring,
                                                           SERVO_TARGET_FRAMES);
                            if (discarded > 0) {
                                atomic_fetch_add(&softResyncCount, 1);
                                atomic_fetch_add(&softResyncFramesDiscarded,
                                                 discarded);
                                printf("SOFT RESYNC: playback resumed after %.1f ms; "
                                       "discarded %llu stale frames (%.1f ms); "
                                       "ring now %llu frames (%.1f ms).\n",
                                       (double)completionGapNs / 1000000.0,
                                       (unsigned long long)discarded,
                                       1000.0 * discarded / 48000.0,
                                       (unsigned long long)audioRingDepth(ring),
                                       1000.0 * audioRingDepth(ring) / 48000.0);
                                fflush(stdout);
                            }
                        }

                        /*
                         * Critical v5.1 change retained: refill and resubmit here,
                         * with no semaphore and no second GCD worker in between.
                         */
                        uint64_t refillStartNs = monotonicNs();
                        fillPlaybackFromRing(playbackBuffers[idx].mutableBytes,
                                             ring);
                        uint64_t refillDoneNs = monotonicNs();

                        if (refillDoneNs > completionNowNs)
                            atomicUpdateMax(&maxPlaybackRefillDelayNs,
                                            refillDoneNs - completionNowNs);
                        else if (refillDoneNs > refillStartNs)
                            atomicUpdateMax(&maxPlaybackRefillDelayNs,
                                            refillDoneNs - refillStartNs);

                        BOOL (^nextPlayback)(NSUInteger) = weakEnqueuePlayback;
                        if (!nextPlayback || !nextPlayback(idx)) {
                            atomic_store(&playbackFatal, true);
                            atomic_store(&workerStop, true);
                        }
                    }];

            if (!queued) {
                atomic_fetch_sub(&playbackPending, 1);
                atomic_fetch_add(&playbackErrors, 1);

                if (!atomic_load(&workerStop)) {
                    fprintf(stderr,
                            "ERROR queueing playback buffer %lu: %s\n",
                            (unsigned long)idx,
                            queueError
                                ? queueError.localizedDescription.UTF8String
                                : "unknown error");
                }

                return NO;
            }

            return YES;
        };
        weakEnqueuePlayback = enqueuePlayback;

        __attribute__((objc_precise_lifetime))
        BOOL (^enqueueCapture)(NSUInteger) = ^BOOL(NSUInteger idx) {
            NSError *queueError = nil;

            atomic_fetch_add(&capturePending, 1);

            BOOL queued =
                [pipe86 enqueueIORequestWithData:captureBuffers[idx]
                              completionTimeout:1.0
                                          error:&queueError
                              completionHandler:
                    ^(IOReturn completionStatus,
                      NSUInteger bytesTransferred) {
                        (void)bytesTransferred;
                        atomic_fetch_sub(&capturePending, 1);

                        if (completionStatus == kIOReturnSuccess) {
                            atomic_fetch_add(&captureTransfers, 1);
                            atomic_store(&lastCaptureSuccessNs, monotonicNs());
                        } else if (!atomic_load(&workerStop) &&
                                   !atomic_load(&suppressResubmit)) {
                            atomic_fetch_add(&captureErrors, 1);
                        }

                        if (!atomic_load(&workerStop) &&
                            !atomic_load(&suppressResubmit)) {
                            BOOL (^nextCapture)(NSUInteger) = weakEnqueueCapture;
                            if (!nextCapture || !nextCapture(idx)) {
                                atomic_store(&playbackFatal, true);
                                atomic_store(&workerStop, true);
                            }
                        }
                    }];

            if (!queued) {
                atomic_fetch_sub(&capturePending, 1);
                atomic_fetch_add(&captureErrors, 1);

                if (!atomic_load(&workerStop)) {
                    fprintf(stderr,
                            "ERROR queueing capture buffer %lu: %s\n",
                            (unsigned long)idx,
                            queueError
                                ? queueError.localizedDescription.UTF8String
                                : "unknown error");
                }

                return NO;
            }

            return YES;
        };
        weakEnqueueCapture = enqueueCapture;

        __attribute__((objc_precise_lifetime))
        BOOL (^enqueueMidi)(void) = ^BOOL(void) {
            NSError *queueError = nil;

            atomic_fetch_add(&midiPending, 1);

            BOOL queued =
                [pipe83 enqueueIORequestWithData:midi
                              completionTimeout:0.5
                                          error:&queueError
                              completionHandler:
                    ^(IOReturn completionStatus,
                      NSUInteger bytesTransferred) {
                        (void)bytesTransferred;
                        atomic_fetch_sub(&midiPending, 1);

                        if (completionStatus == kIOReturnSuccess) {
                            atomic_fetch_add(&midiDrainTransfers, 1);
                            atomic_store(&lastMidiSuccessNs, monotonicNs());

                            if (bytesTransferred > 0 && coreMidi->source) {
                                uint8_t compacted[PLOYTEC_PKT_SIZE];
                                NSUInteger n = 0;
                                const uint8_t *srcBytes = midi.bytes;
                                NSUInteger limit =
                                    bytesTransferred < PLOYTEC_PKT_SIZE
                                        ? bytesTransferred
                                        : PLOYTEC_PKT_SIZE;

                                for (NSUInteger i = 0; i < limit; i++) {
                                    uint8_t b = srcBytes[i];
                                    if (b < 0xF0)
                                        compacted[n++] = b;
                                }

                                if (n > 0)
                                    coreMidiConsumeInputBytes(coreMidi,
                                                              compacted,
                                                              n);
                            }
                        } else if (!atomic_load(&workerStop) &&
                                   !atomic_load(&suppressResubmit)) {
                            atomic_fetch_add(&midiDrainErrors, 1);
                            if (completionStatus == kIOReturnTimeout) {
                                atomic_fetch_add(&midiDrainTimeouts, 1);
                            } else {
                                uint64_t midiErrorNs = monotonicNs();
                                atomic_store(&midiLastOtherStatus,
                                             (int)completionStatus);
                                atomic_store(&midiLastOtherErrorNs,
                                             midiErrorNs);
                                phase4MidiErrorPush(midiErrorNs,
                                                    (int)completionStatus);
                                /* Counter is retained for summary totals. */
                                atomic_fetch_add(&midiDrainOtherErrors, 1);
                            }
                        }

                        if (!atomic_load(&workerStop) &&
                            !atomic_load(&suppressResubmit)) {
                            BOOL (^nextMidi)(void) = weakEnqueueMidi;
                            if (!nextMidi || !nextMidi()) {
                                atomic_store(&playbackFatal, true);
                                atomic_store(&workerStop, true);
                            }
                        }
                    }];

            if (!queued) {
                atomic_fetch_sub(&midiPending, 1);
                atomic_fetch_add(&midiDrainErrors, 1);
                atomic_fetch_add(&midiQueueFailures, 1);

                if (!atomic_load(&workerStop)) {
                    fprintf(stderr,
                            "ERROR queueing MIDI IN request: %s\n",
                            queueError
                                ? queueError.localizedDescription.UTF8String
                                : "unknown error");
                }

                return NO;
            }

            return YES;
        };
        weakEnqueueMidi = enqueueMidi;

        /*
         * Linux-v4-style first recovery rung.  The Linux driver stops the
         * complete request ring, restarts it warm, then gives the restarted
         * stream a 200 ms grace period and requires a real completion cadence.
         *
         * v6.2 keeps the proven v6.1 IOUSBHost recovery path.  The three pipes are aborted
         * asynchronously so we do not serialize three synchronous abort waits;
         * we then wait until every old request has retired before reusing its
         * buffer and queueing a fresh 8/8/1 ring.
         */
        __attribute__((objc_precise_lifetime))
        void (^performWarmRecovery)(void) = ^{
            if (atomic_load(&workerStop))
                return;

            bool expected = false;
            if (!atomic_compare_exchange_strong(&recoveryInProgress,
                                                 &expected,
                                                 true))
                return;

            atomic_fetch_add(&warmRecoveryAttempts, 1);

            uint64_t recoveryStartNs = monotonicNs();
            uint64_t pbLast = atomic_load(&lastPlaybackSuccessNs);
            uint64_t capLast = atomic_load(&lastCaptureSuccessNs);
            uint64_t midiLast = atomic_load(&lastMidiSuccessNs);
            uint64_t ringBefore = audioRingDepth(ring);
            uint64_t bhDiscardStart =
                atomic_load(&ring->recoveryInputFramesDiscarded);

            /*
             * Once recovery is committed, continuity is already broken.
             * Stop accumulating new BlackHole audio so we do not replay the
             * recovery interval late after the USB stream returns.
             */
            atomic_store_explicit(&ring->discardInputDuringRecovery,
                                  true,
                                  memory_order_release);

            double pbAgeMs = pbLast && recoveryStartNs > pbLast
                ? (double)(recoveryStartNs - pbLast) / 1000000.0 : -1.0;
            double capAgeMs = capLast && recoveryStartNs > capLast
                ? (double)(recoveryStartNs - capLast) / 1000000.0 : -1.0;
            double midiAgeMs = midiLast && recoveryStartNs > midiLast
                ? (double)(recoveryStartNs - midiLast) / 1000000.0 : -1.0;

            printf("\nRECOVERY: playback silence %.1f ms; warm all-stream restart\n",
                   pbAgeMs);
            printf("RECOVERY DIAG: capture last success %.1f ms ago; "
                   "MIDI last success %.1f ms ago; pending P/C/M %lu/%lu/%lu; "
                   "ring %llu frames (%.1f ms)\n",
                   capAgeMs,
                   midiAgeMs,
                   atomic_load(&playbackPending),
                   atomic_load(&capturePending),
                   atomic_load(&midiPending),
                   (unsigned long long)ringBefore,
                   1000.0 * ringBefore / 48000.0);
            fflush(stdout);

            /*
             * Fence resubmission before aborting.  Setting the flag alone is
             * not enough: a completion callback may already have passed its
             * flag check.  Both IOUSBHost interface service queues are serial,
             * so draining them here guarantees all pre-flag callbacks have
             * finished before the abort begins.  This is the userspace analogue
             * of Linux setting its stopping flag under the stream lock before
             * killing anchored URBs.
             */
            atomic_store(&suppressResubmit, true);
            atomic_store(&recoveryMonitoring, false);
            dispatch_sync(usbIf0ServiceQueue, ^{});
            dispatch_sync(usbIf1ServiceQueue, ^{});

            NSError *abort05Error = nil;
            NSError *abort86Error = nil;
            NSError *abort83Error = nil;

            uint64_t abortStartNs = monotonicNs();
            BOOL abort05OK =
                [pipe05 abortWithOption:IOUSBHostAbortOptionAsynchronous
                                  error:&abort05Error];
            BOOL abort86OK =
                [pipe86 abortWithOption:IOUSBHostAbortOptionAsynchronous
                                  error:&abort86Error];
            BOOL abort83OK =
                [pipe83 abortWithOption:IOUSBHostAbortOptionAsynchronous
                                  error:&abort83Error];

            uint64_t drainDeadline =
                abortStartNs + RECOVERY_PENDING_DRAIN_NS;

            while (!atomic_load(&workerStop) &&
                   (atomic_load(&playbackPending) != 0 ||
                    atomic_load(&capturePending) != 0 ||
                    atomic_load(&midiPending) != 0) &&
                   monotonicNs() < drainDeadline) {
                usleep(500);
            }

            uint64_t drainedNs = monotonicNs();
            double abortDrainMs =
                drainedNs > abortStartNs
                    ? (double)(drainedNs - abortStartNs) / 1000000.0
                    : 0.0;

            if (!abort05OK || !abort86OK || !abort83OK ||
                atomic_load(&playbackPending) != 0 ||
                atomic_load(&capturePending) != 0 ||
                atomic_load(&midiPending) != 0) {
                fprintf(stderr,
                        "RECOVERY FAILED: abort/drain did not complete cleanly "
                        "in %.1f ms (P/C/M %lu/%lu/%lu).\n",
                        abortDrainMs,
                        atomic_load(&playbackPending),
                        atomic_load(&capturePending),
                        atomic_load(&midiPending));
                if (!abort05OK && abort05Error)
                    fprintf(stderr, "  0x05 abort: %s\n",
                            abort05Error.localizedDescription.UTF8String);
                if (!abort86OK && abort86Error)
                    fprintf(stderr, "  0x86 abort: %s\n",
                            abort86Error.localizedDescription.UTF8String);
                if (!abort83OK && abort83Error)
                    fprintf(stderr, "  0x83 abort: %s\n",
                            abort83Error.localizedDescription.UTF8String);

                atomic_fetch_add(&warmRecoveryFailures, 1);
                atomic_store(&playbackFatal, true);
                atomic_store(&recoveryInProgress, false);
                return;
            }

            /*
             * The USB consumer is now fully stopped, so readFrame has a single
             * owner.  Drop only the oldest excess backlog.  RECOVERY_RETAIN_FRAMES
             * includes the 8 initial playback requests plus the 4 completions
             * required by the health proof, leaving us near SERVO_TARGET_FRAMES
             * when recovery is declared healthy.
             */
            uint64_t staleRingDiscard =
                audioRingTrimOldestToDepth(ring, RECOVERY_RETAIN_FRAMES);
            if (staleRingDiscard > 0) {
                printf("RECOVERY RESYNC: discarded %llu stale queued frames "
                       "(%.1f ms); retained %llu frames before restart.\n",
                       (unsigned long long)staleRingDiscard,
                       1000.0 * staleRingDiscard / 48000.0,
                       (unsigned long long)audioRingDepth(ring));
                fflush(stdout);
            }

            atomic_store(&recoveryFirstPlaybackNs, 0);
            atomic_store(&recoveryLastPlaybackNs, 0);
            atomic_store(&recoveryPlaybackCompletions, 0);
            atomic_store(&lastPlaybackCompletionNs, 0);
            atomic_store(&lastPlaybackSuccessNs, 0);

            /* Allow the new completions to keep their rings moving. */
            atomic_store(&suppressResubmit, false);
            atomic_store(&recoveryMonitoring, true);

            BOOL restartOK = YES;

            for (NSUInteger i = 0; i < PLAYBACK_URB_COUNT; i++) {
                if (!enqueueCapture(i)) {
                    restartOK = NO;
                    break;
                }
            }

            if (restartOK && !enqueueMidi())
                restartOK = NO;

            if (restartOK) {
                for (NSUInteger i = 0; i < PLAYBACK_URB_COUNT; i++) {
                    fillPlaybackFromRing(playbackBuffers[i].mutableBytes, ring);
                    if (!enqueuePlayback(i)) {
                        restartOK = NO;
                        break;
                    }
                }
            }

            if (!restartOK) {
                fprintf(stderr,
                        "RECOVERY FAILED: could not queue the fresh USB rings.\n");
                atomic_store(&recoveryMonitoring, false);
                atomic_fetch_add(&warmRecoveryFailures, 1);
                atomic_store(&playbackFatal, true);
                atomic_store(&recoveryInProgress, false);
                return;
            }

            uint64_t restartQueuedNs = monotonicNs();
            uint64_t graceDeadline = restartQueuedNs + RECOVERY_GRACE_NS;
            BOOL healthy = NO;

            while (!atomic_load(&workerStop) &&
                   monotonicNs() < graceDeadline) {
                unsigned long completions =
                    atomic_load(&recoveryPlaybackCompletions);
                uint64_t first =
                    atomic_load(&recoveryFirstPlaybackNs);
                uint64_t last =
                    atomic_load(&recoveryLastPlaybackNs);
                uint64_t now = monotonicNs();

                if (completions >= RECOVERY_MIN_COMPLETIONS &&
                    first != 0 && last > first &&
                    last - first >= RECOVERY_CADENCE_FLOOR_NS &&
                    now >= last && now - last <= RECOVERY_LIVENESS_NS) {
                    healthy = YES;
                    break;
                }

                usleep(500);
            }

            atomic_store(&recoveryMonitoring, false);

            uint64_t recoveryEndNs = monotonicNs();
            uint64_t recoveryDurationNs =
                recoveryEndNs > recoveryStartNs
                    ? recoveryEndNs - recoveryStartNs : 0;
            atomicUpdateMax(&maxWarmRecoveryNs, recoveryDurationNs);

            if (healthy) {
                /* Resume real-time capture only after USB is proven healthy. */
                atomic_store_explicit(&ring->discardInputDuringRecovery,
                                      false,
                                      memory_order_release);
                uint64_t bhDiscardEnd =
                    atomic_load(&ring->recoveryInputFramesDiscarded);
                uint64_t recoveryInputDiscard =
                    bhDiscardEnd >= bhDiscardStart
                        ? bhDiscardEnd - bhDiscardStart : 0;

                atomic_fetch_add(&warmRecoverySuccesses, 1);
                printf("RECOVERY OK: abort/drain %.1f ms; total %.1f ms; "
                       "%lu playback completions proved healthy; "
                       "ring now %llu frames (%.1f ms); "
                       "skipped %llu live frames during recovery (%.1f ms).\n",
                       abortDrainMs,
                       (double)recoveryDurationNs / 1000000.0,
                       atomic_load(&recoveryPlaybackCompletions),
                       (unsigned long long)audioRingDepth(ring),
                       1000.0 * audioRingDepth(ring) / 48000.0,
                       (unsigned long long)recoveryInputDiscard,
                       1000.0 * recoveryInputDiscard / 48000.0);
                fflush(stdout);
            } else {
                atomic_fetch_add(&warmRecoveryFailures, 1);
                fprintf(stderr,
                        "RECOVERY FAILED: warm restart did not reach healthy "
                        "playback within 200 ms (%lu completions).\n",
                        atomic_load(&recoveryPlaybackCompletions));
                /*
                 * Linux would escalate to a full USB device reset here.  On
                 * macOS resetWithError: destroys/re-enumerates the IOUSBHost
                 * device and invalidates our interface/pipe objects, so v6.3
                 * stops here rather than pretending that step is equivalent.
                 */
                atomic_store(&playbackFatal, true);
            }

            atomic_store(&recoveryInProgress, false);
        };

        /*
         * Keep capture and MIDI live before playback.  v7.5 keeps Capture
         * from IOUSBHost's asynchronous GCD completion path: a dedicated
         * time-constraint pthread continuously performs synchronous bulk IN
         * requests.  MIDI remains asynchronous in this experiment.
         */
        atomic_int captureRealtimePolicyResult;
        atomic_init(&captureRealtimePolicyResult, INT_MIN);

        /* Monotonic origin used only to timestamp diagnostic events. */
        uint64_t diagnosticSessionStartNs = monotonicNs();
        NSString *phase4PcmDirectoryObject =
            [NSHomeDirectory() stringByAppendingPathComponent:
                @"Library/Logs/ReloopBridge/Phase4PCM"];
        NSError *phase4DirectoryError = nil;
        BOOL phase4DirectoryReady =
            [[NSFileManager defaultManager]
                createDirectoryAtPath:phase4PcmDirectoryObject
                withIntermediateDirectories:YES
                attributes:nil
                error:&phase4DirectoryError];
        if (!phase4DirectoryReady) {
            fprintf(stderr,
                    "WARNING: Phase 4 PCM directory could not be prepared: %s\n",
                    phase4DirectoryError
                        ? phase4DirectoryError.localizedDescription.UTF8String
                        : "unknown error");
        }
        const char *phase4PcmDirectory =
            phase4PcmDirectoryObject.fileSystemRepresentation;

        RealtimeCaptureContext realtimeCaptureContext = {
            .pipeObject = (__bridge void *)pipe86,
            .bufferObject = (__bridge void *)(captureBuffers[0]),
            .workerStop = &workerStop,
            .captureTransfers = &captureTransfers,
            .captureErrors = &captureErrors,
            .capturePending = &capturePending,
            .lastCaptureSuccessNs = &lastCaptureSuccessNs,
            .maxCaptureSyncDurationNs = &maxCaptureSyncDurationNs,
            .captureSyncOver50ms = &captureSyncOver50ms,
            .captureTimeouts = &captureTimeouts,
            .captureOtherErrors = &captureOtherErrors,
            .captureLastOtherStatus = &captureLastOtherStatus,
            .captureOperationalOver20ms = &captureOperationalOver20ms,
            .captureOperationalOver50ms = &captureOperationalOver50ms,
            .lastSlowCaptureEndNs = &lastSlowCaptureEndNs,
            .lastSlowCaptureDurationNs = &lastSlowCaptureDurationNs,
            .lastSlowCaptureBytes = &lastSlowCaptureBytes,
            .lastSlowCaptureSuccess = &lastSlowCaptureSuccess,
            .lastSlowCapturePlaybackSuccessAgeNs = &lastSlowCapturePlaybackSuccessAgeNs,
            .lastSlowCaptureBhCallbackAgeNs = &lastSlowCaptureBhCallbackAgeNs,
            .lastSlowCaptureMidiSuccessAgeNs = &lastSlowCaptureMidiSuccessAgeNs,
            .lastPlaybackSuccessNs = &lastPlaybackSuccessNs,
            .lastMidiSuccessNs = &lastMidiSuccessNs,
            .ring = ring,
            .realtimePolicyResult = &captureRealtimePolicyResult
        };

        pthread_t realtimeCaptureThread;
        pthread_attr_t realtimeCaptureAttr;
        pthread_attr_init(&realtimeCaptureAttr);
        pthread_attr_set_qos_class_np(&realtimeCaptureAttr,
                                      QOS_CLASS_USER_INTERACTIVE,
                                      0);
        int capturePthreadResult =
            pthread_create(&realtimeCaptureThread,
                           &realtimeCaptureAttr,
                           realtimeCaptureThreadMain,
                           &realtimeCaptureContext);
        pthread_attr_destroy(&realtimeCaptureAttr);

        BOOL realtimeCaptureThreadCreated = (capturePthreadResult == 0);
        BOOL auxiliaryQueueOK = realtimeCaptureThreadCreated;

        if (auxiliaryQueueOK && !enqueueMidi())
            auxiliaryQueueOK = NO;

        if (!auxiliaryQueueOK) {
            fprintf(stderr,
                    "ERROR: initial synchronous capture/MIDI startup failed.\n");
            atomic_store(&workerStop, true);
            NSError *abortError = nil;
            [pipe86 abortWithError:&abortError];
            abortError = nil;
            [pipe83 abortWithError:&abortError];
            if (realtimeCaptureThreadCreated)
                pthread_join(realtimeCaptureThread, NULL);
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 18;
        }

        OSStatus midiStatus = setupCoreMidiBridge(coreMidi, &midiOutRing);
        if (midiStatus != noErr) {
            fprintf(stderr,
                    "ERROR creating CoreMIDI virtual source/destination (OSStatus %d).\n",
                    (int)midiStatus);
            atomic_store(&workerStop, true);
            NSError *abortError = nil;
            [pipe86 abortWithError:&abortError];
            abortError = nil;
            [pipe83 abortWithError:&abortError];
            pthread_join(realtimeCaptureThread, NULL);
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 30;
        }

        printf("CoreMIDI source/destination ready: Reloop Jockey 3 ME (Bridge).\n");

        for (int wait = 0; wait < 100 &&
             atomic_load(&captureRealtimePolicyResult) == INT_MIN; wait++)
            usleep(1000);

        int captureRtResult = atomic_load(&captureRealtimePolicyResult);
        if (captureRtResult == KERN_SUCCESS)
            printf("Real-time capture drain thread: THREAD_TIME_CONSTRAINT_POLICY ACTIVE.\n");
        else
            printf("WARNING: capture real-time policy was not accepted (kern_return_t %d); capture continues at user-interactive QoS.\n",
                   captureRtResult);

        /*
         * Start BlackHole only after the Reloop is completely initialized and
         * its capture/MIDI endpoints are already continuously serviced.
         */
        ast = AudioDeviceStart(blackHole, ioProcID);

        if (ast != noErr) {
            fprintf(stderr,
                    "ERROR starting BlackHole capture (OSStatus %d).\n",
                    (int)ast);
            atomic_store(&workerStop, true);
            NSError *abortError = nil;
            [pipe86 abortWithError:&abortError];
            abortError = nil;
            [pipe83 abortWithError:&abortError];
            disposeCoreMidiBridge(coreMidi);
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 19;
        }

        /*
         * A small controlled prefill gives scheduling headroom without the
         * 1+ second latency that v1 eventually accumulated.
         */
        int prefillLoops = 0;
        while (audioRingDepth(ring) < PLAYBACK_PREFILL_FRAMES &&
               prefillLoops < 2000) {
            usleep(1000);
            prefillLoops++;
        }

        printf("BlackHole capture started. Prefill depth: %llu frames.\n",
               (unsigned long long)audioRingDepth(ring));

        /*
         * v7 architecture test: playback no longer depends on IOUSBHost's
         * dispatch completion queue.  A dedicated pthread performs synchronous
         * bulk writes and is promoted to Mach real-time scheduling.
         */
        atomic_int realtimePolicyResult;
        atomic_init(&realtimePolicyResult, INT_MIN);

        RealtimePlaybackContext realtimePlaybackContext = {
            .pipeObject = (__bridge void *)pipe05,
            .bufferObject = (__bridge void *)(playbackBuffers[0]),
            .ring = ring,
            .workerStop = &workerStop,
            .playbackFatal = &playbackFatal,
            .playbackTransfers = &playbackTransfers,
            .playbackErrors = &playbackErrors,
            .playbackPending = &playbackPending,
            .lastPlaybackCompletionNs = &lastPlaybackCompletionNs,
            .lastPlaybackSuccessNs = &lastPlaybackSuccessNs,
            .maxPlaybackCompletionGapNs = &maxPlaybackCompletionGapNs,
            .playbackGapOver10ms = &playbackGapOver10ms,
            .playbackGapOver50ms = &playbackGapOver50ms,
            .maxPlaybackRefillDelayNs = &maxPlaybackRefillDelayNs,
            .maxSyncWriteDurationNs = &maxSyncWriteDurationNs,
            .syncWriteOver10ms = &syncWriteOver10ms,
            .syncWriteOver20ms = &syncWriteOver20ms,
            .syncWriteOver50ms = &syncWriteOver50ms,
            .playbackTimeouts = &playbackTimeouts,
            .playbackOtherErrors = &playbackOtherErrors,
            .playbackPartialTransfers = &playbackPartialTransfers,
            .playbackLastOtherStatus = &playbackLastOtherStatus,
            .slowWriteOperationalOver20ms = &slowWriteOperationalOver20ms,
            .slowWriteOperationalOver50ms = &slowWriteOperationalOver50ms,
            .lastSlowWriteEndNs = &lastSlowWriteEndNs,
            .lastSlowWriteDurationNs = &lastSlowWriteDurationNs,
            .lastSlowWriteCompletionGapNs = &lastSlowWriteCompletionGapNs,
            .lastSlowWriteRingDepthFrames = &lastSlowWriteRingDepthFrames,
            .lastSlowWriteBytes = &lastSlowWriteBytes,
            .lastSlowWriteAttempt = &lastSlowWriteAttempt,
            .lastSlowWriteSuccess = &lastSlowWriteSuccess,
            .lastSlowWriteBhCallbackAgeNs = &lastSlowWriteBhCallbackAgeNs,
            .lastSlowWriteCaptureSuccessAgeNs = &lastSlowWriteCaptureSuccessAgeNs,
            .lastSlowWriteMidiSuccessAgeNs = &lastSlowWriteMidiSuccessAgeNs,
            .lastSlowWriteIf0ProbeAgeNs = &lastSlowWriteIf0ProbeAgeNs,
            .lastSlowWriteIf1ProbeAgeNs = &lastSlowWriteIf1ProbeAgeNs,
            .lastSlowWriteRecoveryProbeAgeNs = &lastSlowWriteRecoveryProbeAgeNs,
            .lastCaptureSuccessNs = &lastCaptureSuccessNs,
            .lastMidiSuccessNs = &lastMidiSuccessNs,
            .if0ProbeLastNs = &if0ProbeLastNs,
            .if1ProbeLastNs = &if1ProbeLastNs,
            .recoveryProbeLastNs = &recoveryProbeLastNs,
            .softResyncCount = &softResyncCount,
            .softResyncFramesDiscarded = &softResyncFramesDiscarded,
            .catchupRequested = &catchupRequested,
            .midiOutRing = &midiOutRing,
            .realtimePolicyResult = &realtimePolicyResult
        };

        pthread_t realtimePlaybackThread;
        pthread_attr_t realtimePlaybackAttr;
        pthread_attr_init(&realtimePlaybackAttr);
        pthread_attr_set_qos_class_np(&realtimePlaybackAttr,
                                      QOS_CLASS_USER_INTERACTIVE,
                                      0);
        int pthreadResult =
            pthread_create(&realtimePlaybackThread,
                           &realtimePlaybackAttr,
                           realtimePlaybackThreadMain,
                           &realtimePlaybackContext);
        pthread_attr_destroy(&realtimePlaybackAttr);

        if (pthreadResult != 0) {
            fprintf(stderr,
                    "ERROR: could not create real-time playback pthread (%d).\n",
                    pthreadResult);
            atomic_store(&workerStop, true);
            NSError *abortError = nil;
            [pipe86 abortWithError:&abortError];
            abortError = nil;
            [pipe83 abortWithError:&abortError];
            AudioDeviceStop(blackHole, ioProcID);
            disposeCoreMidiBridge(coreMidi);
            [if1 destroy];
            [if0 destroy];
            AudioDeviceDestroyIOProcID(blackHole, ioProcID);
            audioRingDestroy(ring);
            free(ring);
            restoreBlackHoleClock(&adaptiveClock);
            return 20;
        }

        for (int wait = 0; wait < 100 &&
             atomic_load(&realtimePolicyResult) == INT_MIN; wait++)
            usleep(1000);

        int rtResult = atomic_load(&realtimePolicyResult);
        if (rtResult == KERN_SUCCESS)
            printf("Real-time playback thread: THREAD_TIME_CONSTRAINT_POLICY ACTIVE.\n");
        else
            printf("WARNING: real-time playback policy was not accepted (kern_return_t %d); test will continue at user-interactive QoS.\n",
                   rtResult);

        /*
         * v6.3 diagnostic only: put a tiny 10 ms heartbeat directly on each
         * IOUSBHost interface service queue.  A large heartbeat gap means that
         * the serial queue itself was unable to run promptly (because it was
         * descheduled or blocked by another handler), independent of whether
         * the USB device had data ready.  This lets us distinguish a controller
         * stall from userspace queue starvation under normal Mac activity.
         */
        dispatch_source_t if0ProbeTimer =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                   0, 0, usbIf0ServiceQueue);
        dispatch_source_t if1ProbeTimer =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                   0, 0, usbIf1ServiceQueue);

        dispatch_source_set_timer(
            if0ProbeTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)SERVICE_QUEUE_PROBE_NS),
            SERVICE_QUEUE_PROBE_NS,
            SERVICE_QUEUE_PROBE_LEEWAY_NS);
        dispatch_source_set_event_handler(if0ProbeTimer, ^{
            uint64_t now = monotonicNs();
            uint64_t prev = atomic_exchange(&if0ProbeLastNs, now);
            if (prev != 0 && now > prev) {
                uint64_t gap = now - prev;
                atomicUpdateMax(&if0ProbeMaxGapNs, gap);
                if (gap > 20000000ULL) atomic_fetch_add(&if0ProbeOver20ms, 1);
                if (gap > 50000000ULL) atomic_fetch_add(&if0ProbeOver50ms, 1);
            }
        });

        dispatch_source_set_timer(
            if1ProbeTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)SERVICE_QUEUE_PROBE_NS),
            SERVICE_QUEUE_PROBE_NS,
            SERVICE_QUEUE_PROBE_LEEWAY_NS);
        dispatch_source_set_event_handler(if1ProbeTimer, ^{
            uint64_t now = monotonicNs();
            uint64_t prev = atomic_exchange(&if1ProbeLastNs, now);
            if (prev != 0 && now > prev) {
                uint64_t gap = now - prev;
                atomicUpdateMax(&if1ProbeMaxGapNs, gap);
                if (gap > 20000000ULL) atomic_fetch_add(&if1ProbeOver20ms, 1);
                if (gap > 50000000ULL) atomic_fetch_add(&if1ProbeOver50ms, 1);
            }
        });

        dispatch_resume(if0ProbeTimer);
        dispatch_resume(if1ProbeTimer);

        /*
         * Dedicated high-priority liveness watchdog.  Linux v4 uses 20 ms
         * in-kernel.  In this userspace IOUSBHost bridge, short late callbacks
         * are handled by SOFT RESYNC when they return.  Only silence that persists
         * for 60 ms triggers the expensive warm all-stream restart.  Poll every
         * 5 ms and retain the Linux-style 200 ms post-start grace.
         */
        dispatch_queue_attr_t recoveryQueueAttr =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                    QOS_CLASS_USER_INTERACTIVE,
                                                    0);
        dispatch_queue_t recoveryQueue =
            dispatch_queue_create("reloop.usb.recovery", recoveryQueueAttr);
        dispatch_source_t recoveryTimer =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                   0, 0, recoveryQueue);
        __block uint64_t watchdogArmNs =
            monotonicNs() + RECOVERY_GRACE_NS;

        dispatch_source_set_timer(
            recoveryTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)WATCHDOG_POLL_NS),
            WATCHDOG_POLL_NS,
            1000000ULL);

        dispatch_source_set_event_handler(recoveryTimer, ^{
            uint64_t recoveryProbeNowNs = monotonicNs();
            uint64_t recoveryProbePrevNs =
                atomic_exchange(&recoveryProbeLastNs, recoveryProbeNowNs);
            if (recoveryProbePrevNs != 0 &&
                recoveryProbeNowNs > recoveryProbePrevNs) {
                uint64_t recoveryProbeGapNs =
                    recoveryProbeNowNs - recoveryProbePrevNs;
                atomicUpdateMax(&recoveryProbeMaxGapNs, recoveryProbeGapNs);
                if (recoveryProbeGapNs > 20000000ULL)
                    atomic_fetch_add(&recoveryProbeOver20ms, 1);
                if (recoveryProbeGapNs > 50000000ULL)
                    atomic_fetch_add(&recoveryProbeOver50ms, 1);
            }

            /* v7 diagnostic: do not recover from this GCD queue.
             * The real-time playback pthread owns playback liveness. */
            (void)watchdogArmNs;
        });

        dispatch_resume(recoveryTimer);

        printf("\nAUDIO + MIDI BRIDGE ACTIVE\n");
        printf("CoreMIDI In-Port/Out-Port in Traktor: Reloop Jockey 3 ME (Bridge)\n");
        printf("v8.0.7 MIDI OUT behavior unchanged from v8.0.4: actual Tempo Master gates Deck A/B Beat Phase trash LEDs and mirrors phase to the master Play/Pause LED; non-master Play LEDs remain normal.\n");
        printf("Playback transport: one dedicated Mach real-time pthread, synchronous %d-byte bulk writes.\n",
               BATCH_SIZE);
        printf("Set Traktor Audio Device to BlackHole 16ch at 48000 Hz.\n");
        printf("Traktor Master L/R = BlackHole 1/2; Monitor L/R = 4/3.\n");
        printf("Adaptive target ring depth: %d frames (%.1f ms).\n",
               SERVO_TARGET_FRAMES,
               1000.0 * SERVO_TARGET_FRAMES / 48000.0);
        printf("Startup prefill target: %d frames before initial USB queue.\n",
               PLAYBACK_PREFILL_FRAMES);
        printf("Adaptive pitch limit: +/-%.0f ppm; max step %.0f ppm every %d s.\n",
               SERVO_MAX_ABS_PPM,
               SERVO_MAX_STEP_PPM,
               SERVO_INTERVAL_SECONDS);
        printf("Current ring capacity: %d frames (%.1f ms maximum).\n",
               AUDIO_RING_FRAMES,
               1000.0 * AUDIO_RING_FRAMES / 48000.0);
        printf("v8.0.2 audio recovery mode: >50 ms USB writes trigger fixed-rate BlackHole clock catch-up; one zero-byte transport failure is retried with the same audio block.\n");
        printf("v8.0.2: Playback and Capture use dedicated Mach real-time pthreads with synchronous bulk I/O; MIDI remains asynchronous.\n");
        printf("v8.0.2 catch-up limit: -%.1f%% source-clock correction; fixed per event; exit below %.1f ms ring depth.\n",
               CATCHUP_MAX_SLOW_PPM / 10000.0,
               1000.0 * CATCHUP_EXIT_FRAMES / 48000.0);
        printf("v8.0.2 ring capacity is %.1f ms of headroom; normal target remains %.1f ms.\n",
               1000.0 * AUDIO_RING_FRAMES / 48000.0,
               1000.0 * SERVO_TARGET_FRAMES / 48000.0);
        printf("v8.0.7 Phase 4 diagnostics: split USB/MIDI timeout/error classes; correlate playback/capture/BH/MIDI timing; save 10-second pre-USB PCM windows for writes >50 ms; no diagnostic file I/O on real-time threads.\n\n");

        unsigned seconds = 0;
        double servoDepthSum = 0.0;
        unsigned servoDepthSamples = 0;

        uint64_t servoPrevBHCount =
            atomic_load(&ring->callbackCount);
        uint64_t servoPrevBHNs =
            atomic_load(&ring->lastCallbackNs);
        unsigned long servoPrevUSBCount =
            atomic_load(&playbackTransfers);
        uint64_t servoPrevUSBNs =
            atomic_load(&lastPlaybackSuccessNs);

        uint64_t servoAdjustments = 0;
        uint64_t servoSkippedWindows = 0;

        BOOL catchupActive = NO;
        double catchupBaselinePpm = 0.0;
        double catchupFixedCorrectionPpm = 0.0;
        uint64_t catchupEvents = 0;
        uint64_t catchupSeconds = 0;
        double catchupMaxCorrectionPpm = 0.0;
        unsigned catchupStableSeconds = 0;

        while (!gStop && !atomic_load(&playbackFatal)) {
            sleep(1);
            seconds++;

            if (gPhase4ManualPcmRequest) {
                gPhase4ManualPcmRequest = 0;
                uint64_t manualCenter =
                    atomic_load_explicit(&gPhase4PcmRing.writeFrame,
                                         memory_order_acquire);
                const uint64_t requiredPreFrames =
                    (uint64_t)SAMPLE_RATE * PHASE4_PCM_PRE_SECONDS;
                if (manualCenter < requiredPreFrames) {
                    printf("PCM DIAG MANUAL REQUEST IGNORED: fewer than %u seconds of pre-USB PCM are available.\n",
                           (unsigned)PHASE4_PCM_PRE_SECONDS);
                } else {
                    phase4PcmTriggerPush(monotonicNs(), 0, manualCenter);
                    printf("PCM DIAG MANUAL REQUEST: snapshot centered at source frame %llu; save will occur after %u seconds of post-trigger PCM.\n",
                           (unsigned long long)manualCenter,
                           (unsigned)PHASE4_PCM_POST_SECONDS);
                }
                fflush(stdout);
            }

            uint64_t currentDepth = audioRingDepth(ring);
            servoDepthSum += (double)currentDepth;
            servoDepthSamples++;

            BOOL newCatchupRequest =
                atomic_exchange(&catchupRequested, false);

            if (newCatchupRequest) {
                if (currentDepth > CATCHUP_EXIT_FRAMES) {
                    if (!catchupActive) {
                        catchupActive = YES;
                        catchupBaselinePpm =
                            pitchToPpm(adaptiveClock.currentPitch);
                        catchupEvents++;
                    }

                    double excessFrames =
                        (double)(currentDepth - SERVO_TARGET_FRAMES);
                    double requestedCorrectionPpm =
                        -(excessFrames /
                          CATCHUP_TARGET_SECONDS /
                          (double)SAMPLE_RATE) * 1000000.0;

                    if (requestedCorrectionPpm < -CATCHUP_MAX_SLOW_PPM)
                        requestedCorrectionPpm = -CATCHUP_MAX_SLOW_PPM;
                    if (requestedCorrectionPpm > -CATCHUP_MIN_SLOW_PPM)
                        requestedCorrectionPpm = -CATCHUP_MIN_SLOW_PPM;

                    /*
                     * v7.4 holds one correction for the whole catch-up instead
                     * of recomputing a progressively smaller value each second.
                     * If another long USB write happens while catching up, only
                     * strengthen the correction; never weaken it.
                     */
                    if (catchupFixedCorrectionPpm == 0.0 ||
                        requestedCorrectionPpm < catchupFixedCorrectionPpm) {
                        catchupFixedCorrectionPpm =
                            requestedCorrectionPpm;
                    }

                    if (fabs(catchupFixedCorrectionPpm) >
                        catchupMaxCorrectionPpm)
                        catchupMaxCorrectionPpm =
                            fabs(catchupFixedCorrectionPpm);

                    printf("CLOCK CATCHUP START: ring %llu frames (%.1f ms), baseline %+.1f ppm, fixed correction %+.1f ppm.\n",
                           (unsigned long long)currentDepth,
                           1000.0 * currentDepth / 48000.0,
                           catchupBaselinePpm,
                           catchupFixedCorrectionPpm);

                    catchupStableSeconds = 0;
                }
            }

            if (catchupActive) {
                catchupSeconds++;

                if (currentDepth <= CATCHUP_EXIT_FRAMES)
                    catchupStableSeconds++;
                else
                    catchupStableSeconds = 0;

                if (catchupStableSeconds >= 2) {
                    if (!setBlackHolePitch(&adaptiveClock,
                                           ppmToPitch(catchupBaselinePpm))) {
                        fprintf(stderr,
                                "ERROR: could not restore BlackHole pitch after clock catch-up.\n");
                        atomic_store(&playbackFatal, true);
                    } else {
                        printf("CLOCK CATCHUP DONE: ring %llu frames (%.1f ms), restored %+.1f ppm.\n",
                               (unsigned long long)currentDepth,
                               1000.0 * currentDepth / 48000.0,
                               catchupBaselinePpm);
                    }

                    catchupActive = NO;
                    catchupStableSeconds = 0;
                    catchupFixedCorrectionPpm = 0.0;

                    /* Restart normal-servo measurement from a clean window. */
                    servoPrevBHCount =
                        atomic_load(&ring->callbackCount);
                    servoPrevBHNs =
                        atomic_load(&ring->lastCallbackNs);
                    servoPrevUSBCount =
                        atomic_load(&playbackTransfers);
                    servoPrevUSBNs =
                        atomic_load(&lastPlaybackSuccessNs);
                    servoDepthSum = 0.0;
                    servoDepthSamples = 0;
                } else {
                    double catchupPpm =
                        clampDouble(catchupBaselinePpm +
                                    catchupFixedCorrectionPpm,
                                    -10000.0, 10000.0);

                    if (fabs(pitchToPpm(adaptiveClock.currentPitch) -
                             catchupPpm) >= 10.0) {
                        if (!setBlackHolePitch(&adaptiveClock,
                                               ppmToPitch(catchupPpm))) {
                            fprintf(stderr,
                                    "ERROR: BlackHole clock catch-up update failed.\n");
                            atomic_store(&playbackFatal, true);
                        }
                    }
                }
            }

            /*
             * v8.0.7: drain every queued slow-event snapshot from the ordinary
             * main thread.  Real-time threads only publish fixed-size records.
             */
            Phase4PlaybackDiagEvent playbackEvent;
            while (phase4PlaybackEventPop(&playbackEvent)) {
                double eventSeconds =
                    (playbackEvent.eventEndNs > diagnosticSessionStartNs)
                        ? (double)(playbackEvent.eventEndNs -
                                   diagnosticSessionStartNs) / 1e9
                        : 0.0;
                printf("USB DIAG PLAYBACK #%llu: T+%.3fs write %.3f ms, completion gap %.3f ms, bytes %lu, attempt %lu, result %s, ring %llu (%.1f ms), ages at completion: BH %.3f ms, capture-success %.3f ms, MIDI-success %.3f ms, if0-probe %.3f ms, if1-probe %.3f ms, recovery-probe %.3f ms.\n",
                       (unsigned long long)playbackEvent.sequence,
                       eventSeconds,
                       (double)playbackEvent.writeDurationNs / 1e6,
                       (double)playbackEvent.completionGapNs / 1e6,
                       playbackEvent.bytesTransferred,
                       playbackEvent.attempt,
                       playbackEvent.success ? "success" : "failure",
                       (unsigned long long)playbackEvent.ringDepthFrames,
                       1000.0 * playbackEvent.ringDepthFrames / 48000.0,
                       (double)playbackEvent.bhCallbackAgeNs / 1e6,
                       (double)playbackEvent.captureSuccessAgeNs / 1e6,
                       (double)playbackEvent.midiSuccessAgeNs / 1e6,
                       (double)playbackEvent.if0ProbeAgeNs / 1e6,
                       (double)playbackEvent.if1ProbeAgeNs / 1e6,
                       (double)playbackEvent.recoveryProbeAgeNs / 1e6);
            }

            Phase4CaptureDiagEvent captureEvent;
            while (phase4CaptureEventPop(&captureEvent)) {
                double eventSeconds =
                    (captureEvent.eventEndNs > diagnosticSessionStartNs)
                        ? (double)(captureEvent.eventEndNs -
                                   diagnosticSessionStartNs) / 1e9
                        : 0.0;
                printf("USB DIAG CAPTURE #%llu: T+%.3fs read %.3f ms, bytes %lu, result %s, ages at completion: playback-success %.3f ms, BH %.3f ms, MIDI-success %.3f ms.\n",
                       (unsigned long long)captureEvent.sequence,
                       eventSeconds,
                       (double)captureEvent.durationNs / 1e6,
                       captureEvent.bytesTransferred,
                       captureEvent.success ? "success" : "failure",
                       (double)captureEvent.playbackSuccessAgeNs / 1e6,
                       (double)captureEvent.bhCallbackAgeNs / 1e6,
                       (double)captureEvent.midiSuccessAgeNs / 1e6);
            }

            Phase4MidiErrorEvent midiErrorEvent;
            while (phase4MidiErrorPop(&midiErrorEvent)) {
                double eventSeconds =
                    (midiErrorEvent.eventNs > diagnosticSessionStartNs)
                        ? (double)(midiErrorEvent.eventNs -
                                   diagnosticSessionStartNs) / 1e9
                        : 0.0;
                printf("MIDI DIAG ERROR #%llu: T+%.3fs non-timeout completion IOReturn 0x%08x.\n",
                       (unsigned long long)midiErrorEvent.sequence,
                       eventSeconds,
                       (unsigned int)midiErrorEvent.status);
            }

            for (;;) {
                Phase4PcmTrigger pcmEvent;
                if (!phase4PcmTriggerPeek(&pcmEvent))
                    break;

                int pcmResult =
                    phase4WritePcmSnapshot(&pcmEvent,
                                           phase4PcmDirectory,
                                           diagnosticSessionStartNs);
                if (pcmResult == 0)
                    break;
                if (pcmResult == -1) {
                    fprintf(stderr,
                            "PCM DIAG DROPPED #%llu: rolling buffer window expired before it could be written.\n",
                            (unsigned long long)pcmEvent.sequence);
                } else if (pcmResult == -2) {
                    fprintf(stderr,
                            "PCM DIAG ERROR #%llu: could not write snapshot under %s.\n",
                            (unsigned long long)pcmEvent.sequence,
                            phase4PcmDirectory);
                }
                phase4PcmTriggerPop();
            }

            printf("T+%4us | Ring: %5llu (%6.1f ms) | drop:%llu under:%llu | "
                   "USB:%lu maxgap:%5.1fms write:%5.1fms W50:%lu refill:%5.1fms | "
                   "Q0:%5.1f Q1:%5.1f RQ:%5.1fms | "
                   "BH: maxfrm:%llu maxgap:%5.1fms | pitch:%+.0fppm %s\n",
                   seconds,
                   (unsigned long long)currentDepth,
                   1000.0 * currentDepth / 48000.0,
                   (unsigned long long)atomic_load(&ring->framesDropped),
                   (unsigned long long)atomic_load(&ring->underrunFrames),
                   atomic_load(&playbackPending),
                   (double)atomic_load(&maxPlaybackCompletionGapNs) / 1000000.0,
                   (double)atomic_load(&maxSyncWriteDurationNs) / 1000000.0,
                   atomic_load(&syncWriteOver50ms),
                   (double)atomic_load(&maxPlaybackRefillDelayNs) / 1000000.0,
                   (double)atomic_load(&if0ProbeMaxGapNs) / 1000000.0,
                   (double)atomic_load(&if1ProbeMaxGapNs) / 1000000.0,
                   (double)atomic_load(&recoveryProbeMaxGapNs) / 1000000.0,
                   (unsigned long long)atomic_load(&ring->maxCallbackFrames),
                   (double)atomic_load(&ring->maxCallbackGapNs) / 1000000.0,
                   pitchToPpm(adaptiveClock.currentPitch),
                   catchupActive ? "CATCHUP" : "");

            if (seconds % SERVO_INTERVAL_SECONDS == 0 && !catchupActive) {
                uint64_t bhCount =
                    atomic_load(&ring->callbackCount);
                uint64_t bhNs =
                    atomic_load(&ring->lastCallbackNs);
                unsigned long usbCount =
                    atomic_load(&playbackTransfers);
                uint64_t usbNs =
                    atomic_load(&lastPlaybackSuccessNs);

                double averageDepth =
                    servoDepthSamples > 0
                        ? servoDepthSum / (double)servoDepthSamples
                        : (double)currentDepth;

                BOOL measurementOK =
                    servoPrevBHNs != 0 &&
                    servoPrevUSBNs != 0 &&
                    bhNs > servoPrevBHNs &&
                    usbNs > servoPrevUSBNs &&
                    bhCount > servoPrevBHCount &&
                    usbCount > servoPrevUSBCount;

                if (measurementOK) {
                    double bhSeconds =
                        (double)(bhNs - servoPrevBHNs) / 1000000000.0;
                    double usbSeconds =
                        (double)(usbNs - servoPrevUSBNs) / 1000000000.0;

                    double sourceRate =
                        ((double)(bhCount - servoPrevBHCount) * 512.0) /
                        bhSeconds;
                    double sinkRate =
                        ((double)(usbCount - servoPrevUSBCount) *
                         (double)PLAYBACK_AUDIO_FRAMES) /
                        usbSeconds;

                    double measuredMismatchPpm =
                        (sinkRate / sourceRate - 1.0) * 1000000.0;

                    if (isfinite(sourceRate) &&
                        isfinite(sinkRate) &&
                        isfinite(measuredMismatchPpm) &&
                        fabs(measuredMismatchPpm) <=
                            SERVO_MAX_MEASURED_MISMATCH_PPM) {

                        double currentPpm =
                            pitchToPpm(adaptiveClock.currentPitch);

                        /*
                         * Feed-forward from the measured clock-rate difference.
                         */
                        double requestedPpm =
                            currentPpm + measuredMismatchPpm;

                        /*
                         * Slow ring-centering term. Use the 10-second mean so
                         * the controller does not chase the 512-frame callback
                         * sawtooth.
                         */
                        double depthError =
                            (double)SERVO_TARGET_FRAMES - averageDepth;
                        double depthBiasPpm =
                            (depthError /
                             SERVO_DEPTH_RECOVERY_SECONDS /
                             (double)SAMPLE_RATE) * 1000000.0;

                        depthBiasPpm =
                            clampDouble(depthBiasPpm,
                                        -SERVO_MAX_DEPTH_BIAS_PPM,
                                         SERVO_MAX_DEPTH_BIAS_PPM);

                        requestedPpm += depthBiasPpm;
                        requestedPpm =
                            clampDouble(requestedPpm,
                                        -SERVO_MAX_ABS_PPM,
                                         SERVO_MAX_ABS_PPM);

                        double deltaPpm =
                            requestedPpm - currentPpm;
                        deltaPpm =
                            clampDouble(deltaPpm,
                                        -SERVO_MAX_STEP_PPM,
                                         SERVO_MAX_STEP_PPM);

                        double nextPpm =
                            clampDouble(currentPpm + deltaPpm,
                                        -SERVO_MAX_ABS_PPM,
                                         SERVO_MAX_ABS_PPM);

                        if (fabs(nextPpm - currentPpm) >= 0.5) {
                            if (setBlackHolePitch(&adaptiveClock,
                                                  ppmToPitch(nextPpm))) {
                                servoAdjustments++;

                                printf("SERVO: avg %.0f/%d | "
                                       "BH %.3f Hz USB %.3f Hz | "
                                       "mismatch %+.1f ppm bias %+.1f ppm | "
                                       "pitch -> %+.1f ppm\n",
                                       averageDepth,
                                       SERVO_TARGET_FRAMES,
                                       sourceRate,
                                       sinkRate,
                                       measuredMismatchPpm,
                                       depthBiasPpm,
                                       pitchToPpm(adaptiveClock.currentPitch));
                            } else {
                                fprintf(stderr,
                                        "ERROR: BlackHole adaptive pitch update failed.\n");
                                atomic_store(&playbackFatal, true);
                            }
                        } else {
                            printf("SERVO: avg %.0f/%d | "
                                   "BH %.3f Hz USB %.3f Hz | "
                                   "mismatch %+.1f ppm bias %+.1f ppm | "
                                   "pitch steady %+.1f ppm\n",
                                   averageDepth,
                                   SERVO_TARGET_FRAMES,
                                   sourceRate,
                                   sinkRate,
                                   measuredMismatchPpm,
                                   depthBiasPpm,
                                   currentPpm);
                        }
                    } else {
                        servoSkippedWindows++;
                        printf("SERVO: timing window ignored as transient.\n");
                    }
                } else {
                    servoSkippedWindows++;
                    printf("SERVO: waiting for a complete timing window.\n");
                }

                servoPrevBHCount = bhCount;
                servoPrevBHNs = bhNs;
                servoPrevUSBCount = usbCount;
                servoPrevUSBNs = usbNs;
                servoDepthSum = 0.0;
                servoDepthSamples = 0;
            }

            fflush(stdout);
        }

        printf("\nStopping audio + MIDI bridge...\n");

        atomic_store_explicit(&midiOutRing.accepting, false, memory_order_release);
        atomic_store(&workerStop, true);
        dispatch_source_cancel(recoveryTimer);
        dispatch_source_cancel(if0ProbeTimer);
        dispatch_source_cancel(if1ProbeTimer);
        dispatch_sync(recoveryQueue, ^{});
        AudioDeviceStop(blackHole, ioProcID);

        /*
         * Stop all three continuously queued endpoint rings.  workerStop is
         * already set, so abort completions retire without resubmitting.
         */
        NSError *abortError = nil;
        [pipe05 abortWithError:&abortError];
        abortError = nil;
        [pipe86 abortWithError:&abortError];
        abortError = nil;
        [pipe83 abortWithError:&abortError];

        /* The pipe aborts release synchronous reads/writes if shutdown catches them blocked. */
        pthread_join(realtimePlaybackThread, NULL);
        pthread_join(realtimeCaptureThread, NULL);

        /* Give remaining asynchronous MIDI completion handlers a bounded time to retire. */
        for (int i = 0; i < 250; i++) {
            if (atomic_load(&playbackPending) == 0 &&
                atomic_load(&capturePending) == 0 &&
                atomic_load(&midiPending) == 0)
                break;
            usleep(10000);
        }

        disposeCoreMidiBridge(coreMidi);

        uint8_t cleanupStatus = 0;
        error = nil;

        if (getStatus(if0, &cleanupStatus, &error)) {
            uint8_t stopped = cleanupStatus & (uint8_t)~0x20;
            NSError *stopError = nil;

            if (setStatus(if0, stopped, &stopError))
                printf("Streaming stopped: 0x%02x -> 0x%02x\n",
                       cleanupStatus, stopped);
        }

        AudioDeviceDestroyIOProcID(blackHole, ioProcID);

        printf("Adaptive servo adjustments: %llu; skipped windows: %llu; "
               "final pitch: %+.1f ppm\n",
               (unsigned long long)servoAdjustments,
               (unsigned long long)servoSkippedWindows,
               pitchToPpm(adaptiveClock.currentPitch));

        restoreBlackHoleClock(&adaptiveClock);

        printf("Automatic stale-audio trims (disabled in v8.0.2): %lu; frames discarded: %llu\n",
               atomic_load(&softResyncCount),
               (unsigned long long)atomic_load(&softResyncFramesDiscarded));
        printf("Clock catch-up events: %llu; active seconds: %llu; max temporary correction: %.1f ppm\n",
               (unsigned long long)catchupEvents,
               (unsigned long long)catchupSeconds,
               catchupMaxCorrectionPpm);
        printf("Warm recovery attempts (disabled in v7): %lu; successes: %lu; failures: %lu; "
               "max recovery time: %.3f ms\n",
               atomic_load(&warmRecoveryAttempts),
               atomic_load(&warmRecoverySuccesses),
               atomic_load(&warmRecoveryFailures),
               (double)atomic_load(&maxWarmRecoveryNs) / 1000000.0);
        printf("Playback transfers: %lu; errors: %lu; pending: %lu\n",
               atomic_load(&playbackTransfers),
               atomic_load(&playbackErrors),
               atomic_load(&playbackPending));
        printf("Capture drain transfers: %lu; errors: %lu; pending: %lu\n",
               atomic_load(&captureTransfers),
               atomic_load(&captureErrors),
               atomic_load(&capturePending));
        printf("Synchronous capture read duration: max %.3f ms; raw over-50ms %lu; operational over-20ms %lu; operational over-50ms %lu; timeouts %lu; other errors %lu\n",
               (double)atomic_load(&maxCaptureSyncDurationNs) / 1000000.0,
               atomic_load(&captureSyncOver50ms),
               atomic_load(&captureOperationalOver20ms),
               atomic_load(&captureOperationalOver50ms),
               atomic_load(&captureTimeouts),
               atomic_load(&captureOtherErrors));
        if (atomic_load(&captureOtherErrors) > 0) {
            printf("Capture last non-timeout IOUSBHost/other NSError code: 0x%08x\n",
                   (unsigned int)atomic_load(&captureLastOtherStatus));
        }
        printf("MIDI drain transfers: %lu; timeouts: %lu; other completion errors: %lu; queue submission failures: %lu; legacy combined errors/timeouts: %lu; pending: %lu\n",
               atomic_load(&midiDrainTransfers),
               atomic_load(&midiDrainTimeouts),
               atomic_load(&midiDrainOtherErrors),
               atomic_load(&midiQueueFailures),
               atomic_load(&midiDrainErrors),
               atomic_load(&midiPending));
        if (atomic_load(&midiDrainOtherErrors) > 0) {
            uint64_t eventNs = atomic_load(&midiLastOtherErrorNs);
            double eventSeconds =
                (eventNs > diagnosticSessionStartNs)
                    ? (double)(eventNs - diagnosticSessionStartNs) / 1e9
                    : 0.0;
            printf("MIDI last non-timeout completion error: IOReturn 0x%08x at T+%.3fs\n",
                   (unsigned int)atomic_load(&midiLastOtherStatus),
                   eventSeconds);
        }
        printf("CoreMIDI IN forwarded: %lu complete messages; %lu CoreMIDI packets; %lu bytes; errors: %lu\n",
               atomic_load(&coreMidi->midiInMessagesForwarded),
               atomic_load(&coreMidi->midiInBatchesForwarded),
               atomic_load(&coreMidi->midiInBytesForwarded),
               atomic_load(&coreMidi->midiInForwardErrors));
        printf("CoreMIDI OUT received: %lu packets; %lu bytes; "
               "wire bytes sent: %lu; dropped: %lu; queued: %llu\n",
               atomic_load(&midiOutRing.coreMidiPacketsReceived),
               atomic_load(&midiOutRing.bytesReceived),
               atomic_load(&midiOutRing.wireBytesSent),
               atomic_load(&midiOutRing.bytesDropped),
               (unsigned long long)midiOutRingDepth(&midiOutRing));
        printf("Tempo Master LED gate: master-state messages consumed: %lu; "
               "Beat Phase forwarded: %lu; blocked: %lu\n",
               atomic_load(&coreMidi->masterStateMessagesFiltered),
               atomic_load(&coreMidi->beatPhaseMessagesForwarded),
               atomic_load(&coreMidi->beatPhaseMessagesBlocked));
        printf("Tempo Master Play LED mirror: phase messages mirrored: %lu; "
               "ordinary Play LED messages suppressed while master: %lu; "
               "ordinary Play states restored: %lu\n",
               atomic_load(&coreMidi->playLedMessagesMirrored),
               atomic_load(&coreMidi->playLedMessagesSuppressed),
               atomic_load(&coreMidi->playLedStateRestores));
        printf("BlackHole frames accepted: %llu\n",
               (unsigned long long)atomic_load(&ring->framesReceived));
        printf("BlackHole frames dropped: %llu\n",
               (unsigned long long)atomic_load(&ring->framesDropped));
        printf("Playback underrun frames: %llu\n",
               (unsigned long long)atomic_load(&ring->underrunFrames));
        printf("BlackHole callbacks: %llu; max frames/callback: %llu\n",
               (unsigned long long)atomic_load(&ring->callbackCount),
               (unsigned long long)atomic_load(&ring->maxCallbackFrames));
        printf("BlackHole callback gap: min %.3f ms; max %.3f ms; "
               "under-5ms %llu; over-20ms %llu\n",
               (double)atomic_load(&ring->minCallbackGapNs) / 1000000.0,
               (double)atomic_load(&ring->maxCallbackGapNs) / 1000000.0,
               (unsigned long long)atomic_load(&ring->callbackGapUnder5ms),
               (unsigned long long)atomic_load(&ring->callbackGapOver20ms));
        printf("Playback completion max gap: %.3f ms; "
               "over-10ms %llu; over-50ms %llu\n",
               (double)atomic_load(&maxPlaybackCompletionGapNs) / 1000000.0,
               (unsigned long long)atomic_load(&playbackGapOver10ms),
               (unsigned long long)atomic_load(&playbackGapOver50ms));
        printf("Playback max completion-to-refill-finished delay: %.3f ms\n",
               (double)atomic_load(&maxPlaybackRefillDelayNs) / 1000000.0);
        printf("Synchronous USB write duration: max %.3f ms; "
               "raw over-10ms %lu; raw over-20ms %lu; raw over-50ms %lu; "
               "operational over-20ms %lu; operational over-50ms %lu; "
               "timeouts %lu; other errors %lu; partial transfers %lu\n",
               (double)atomic_load(&maxSyncWriteDurationNs) / 1000000.0,
               atomic_load(&syncWriteOver10ms),
               atomic_load(&syncWriteOver20ms),
               atomic_load(&syncWriteOver50ms),
               atomic_load(&slowWriteOperationalOver20ms),
               atomic_load(&slowWriteOperationalOver50ms),
               atomic_load(&playbackTimeouts),
               atomic_load(&playbackOtherErrors),
               atomic_load(&playbackPartialTransfers));
        if (atomic_load(&playbackOtherErrors) > 0) {
            printf("Playback last non-timeout IOUSBHost/other NSError code: 0x%08x\n",
                   (unsigned int)atomic_load(&playbackLastOtherStatus));
        }
        printf("Phase 4 diagnostic event queue drops: playback %llu; capture %llu; MIDI %llu\n",
               (unsigned long long)atomic_load(&gPhase4PlaybackEvents.dropped),
               (unsigned long long)atomic_load(&gPhase4CaptureEvents.dropped),
               (unsigned long long)atomic_load(&gPhase4MidiErrorEvents.dropped));
        printf("Phase 4 PCM trigger queue drops: %llu; snapshots are stored under %s\n",
               (unsigned long long)atomic_load(&gPhase4PcmTriggers.dropped),
               phase4PcmDirectory);
        printf("Queue probe if0: max %.3f ms; over-20ms %lu; over-50ms %lu\n",
               (double)atomic_load(&if0ProbeMaxGapNs) / 1000000.0,
               atomic_load(&if0ProbeOver20ms),
               atomic_load(&if0ProbeOver50ms));
        printf("Queue probe if1: max %.3f ms; over-20ms %lu; over-50ms %lu\n",
               (double)atomic_load(&if1ProbeMaxGapNs) / 1000000.0,
               atomic_load(&if1ProbeOver20ms),
               atomic_load(&if1ProbeOver50ms));
        printf("Queue probe recovery: max %.3f ms; over-20ms %lu; over-50ms %lu\n",
               (double)atomic_load(&recoveryProbeMaxGapNs) / 1000000.0,
               atomic_load(&recoveryProbeOver20ms),
               atomic_load(&recoveryProbeOver50ms));
        printf("Maximum ring depth observed: %llu frames (%.1f ms)\n",
               (unsigned long long)atomic_load(&ring->maxDepthFrames),
               1000.0 * atomic_load(&ring->maxDepthFrames) / 48000.0);
        printf("Final ring depth: %llu frames (%.1f ms)\n",
               (unsigned long long)audioRingDepth(ring),
               1000.0 * audioRingDepth(ring) / 48000.0);

        [if1 destroy];
        [if0 destroy];
        audioRingDestroy(ring);
        free(ring);

        printf("Audio + MIDI bridge stopped cleanly.\n");
    }

    return 0;
}
