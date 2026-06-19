// midiController.ts
// Phase 19 — Hardware: Web MIDI API integration.
// Maps MIDI controller buttons/knobs to timeline actions.

export type MidiCallback = (event: { type: 'noteon' | 'noteoff' | 'cc'; channel: number; note?: number; controller?: number; value: number }) => void;

class MidiController {
  private access: any = null;
  private listeners: Set<MidiCallback> = new Set();
  private enabled = false;

  async enable(): Promise<boolean> {
    if (this.enabled) return true;
    if (typeof navigator === 'undefined' || !(navigator as any).requestMIDIAccess) {
      console.warn('[MIDI] Web MIDI API not supported');
      return false;
    }
    try {
      this.access = await (navigator as any).requestMIDIAccess({ sysex: false });
      this.enabled = true;
      this.access.inputs.forEach((input: any) => {
        input.onmidimessage = (msg: any) => this.handleMessage(msg);
      });
      // Listen for new devices
      this.access.onstatechange = (e: any) => {
        if (e.port.type === 'input' && e.port.state === 'connected') {
          e.port.onmidimessage = (msg: any) => this.handleMessage(msg);
        }
      };
      return true;
    } catch (e) {
      console.error('[MIDI] Access denied:', e);
      return false;
    }
  }

  private handleMessage(msg: any) {
    const [statusByte, d1, d2] = msg.data;
    const status = statusByte & 0xf0;
    const channel = (statusByte & 0x0f) + 1;
    const event: any = { channel, value: d2 ?? 0 };
    if (status === 0x90 && d2 > 0) event.type = 'noteon', event.note = d1;
    else if (status === 0x80 || (status === 0x90 && d2 === 0)) event.type = 'noteoff', event.note = d1;
    else if (status === 0xb0) event.type = 'cc', event.controller = d1;
    else return;
    this.listeners.forEach((cb) => cb(event));
  }

  onMessage(cb: MidiCallback): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  listDevices(): Array<{ id: string; name: string; manufacturer: string }> {
    if (!this.access) return [];
    return Array.from(this.access.inputs.values()).map((input: any) => ({
      id: input.id,
      name: input.name,
      manufacturer: input.manufacturer,
    }));
  }

  isEnabled(): boolean {
    return this.enabled;
  }
}

export const midiController = new MidiController();

// Built-in mappings: standard transport controls (matches many MIDI controllers)
export const DEFAULT_MAPPINGS: Record<string, string> = {
  'cc:64': 'playback.play',           // Sustain pedal / play
  'cc:65': 'playback.pause',          // Stop
  'cc:66': 'playback.toggle_fullscreen',
  'cc:67': 'timeline.undo',
  'cc:68': 'timeline.redo',
  'noteon:60': 'timeline.add_marker', // C3
  'noteon:62': 'timeline.split_clip', // D3
  'noteon:64': 'timeline.delete_clip',// E3
};

export function buildMappingKey(event: { type: string; controller?: number; note?: number }): string {
  return `${event.type}:${event.controller ?? event.note}`;
}
