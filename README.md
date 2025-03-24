# CHROMA

### Overivew
Chroma is a stereo additive synthesiser that blends two user-defined harmonic spectra—Wave A and Wave B—using morphing techniques modulated by an LFO or envelope. The name Chroma references chromaticity: the progression from grayscale to full colour saturation. In this context, it symbolises the sonic transition between two spectral states, offering expressive control through harmonic interpolation. The name reflects both the spectral design and the aesthetic goal of enabling a dynamic timbral palette.

### Harmonic Oscillator
The synth uses 16 harmonics. Two independent harmonic tables (A and B) define the amplitude of each partial. By default, Table A is loaded with a saw wave (all harmonics), and Table B with a square wave (odd harmonics only). The user can select which table to edit using a menu and sliders. Morphing between tables is controlled by an LFO or an envelope.

### Filter
A custom filter section provides three selectable modes—high-pass, low-pass, and band-pass— using toggle controls. Both cutoff frequency and resonance (Q) can be modulated via envelope or LFO. Frequency modulation is shaped nonlinearly for improved control in the low-frequency range.

### Modulation
- The LFO can smoothly morph between sine, triangle, and saw wave shapes using a sigmoid blending function.
- Two independent ADSRs are used: one for amplitude, and one assignable to modulation targets such as the filter frequency and resonance or oscillator morphing.

### Effects
The synthesiser features three effects, controlled via toggles and dials:
- Flanger: classic delay-line flanger modulated by a triangle LFO.
- Glimmer: a custom chorus effect using four short delay lines with cross-feedback and LFO modulation for subtle stereo widening.
- Delay: Stereo ping-pong delay with time, feedback, and gain control.

### GUI controls
![GUI](https://github.com/dohmansfi/Chroma/tree/47b3421a3c32975f730be9b5a4a83e7e66771241/img/GUI.jpeg)

1.
2.
3.
4.
5.
6.
7.
8.
9.
