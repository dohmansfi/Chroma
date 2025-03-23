
#include <klang.h>
using namespace klang::optimised;

signal nonlinear(signal x){
    return pow(10, 2 * (x - 1));
}

#define N_HARMONICS 16

struct HarmonicTable {
	float amplitude[N_HARMONICS];
};

HarmonicTable tableA {
	{ 1.0, 0.0, 0.6, 0.0, 0.4, 0.0, 0.2, 0.7, 0.1, 0.08, 0.07, 0.05, 0.04, 0.03, 0.02, 0.01 }
};

HarmonicTable tableB {
	{ 1.0, 0.6, 0.0, 0.3, 0.0, 0.15, 0.0, 0.08, 0.06, 0.05, 0.04, 0.03, 0.02, 0.015, 0.01, 0.005 }
};

struct LFO : Modifier {
	Sine sin;
	Triangle tri;
	Saw saw;
	LPF lpf;
	signal lfo;
	
	signal sigmoidBlend(param position, float center, float sharpness = 10.0) {
		return 1.0 / (1.0 + exp(-sharpness * (position - center)));
	}
	
	void set(param rate, param shape) {
		// compute smooth blending weights using sigmoid curves
        signal blend1 = sigmoidBlend(shape, 0.5);  // sine to triangle
        signal blend2 = sigmoidBlend(shape, 1.5);  // triangle to saw
		
		// mod signals
        signal sinMod = sin(rate) * 0.5 + 0.5;
        signal triMod = tri(rate) * 0.5 + 0.5;
        signal sawMod = saw(rate) * 0.5 + 0.5;
        signal pseudoSaw = sawMod >> lpf(500);
;        lfo = (1.0 - blend1) * sinMod + (blend1 - blend2) * triMod + blend2 * pseudoSaw;
	}
	
	void process() {
		lfo >> out;
	}
};

struct Filter : Effect {
	HPF hpf;
	LPF lpf;
	BPF bpf;
	
	void set(param f, param q){
	}
	
	void process(){
	}
};

struct Vibrato : Effect {
};

struct Flanger : Effect {
	Delay<192000> delay;
	Triangle lfo;
	signal mod;
	
	void set(param rate, param depth) {
//		param depth = controls[1] / 1000.f;
		mod = lfo(rate) * depth + depth;
	}

	void process() {	
		in + (in >> delay)(mod * fs) >> out;
	}
};

struct Chorus : Effect {
};

struct Delay : Effect {
};

struct ChromaOsc : Oscillator {
	Sine harmonic[N_HARMONICS];
	param gain[N_HARMONICS];
	
	void set(param frequency) {
		for (int h = 0; h < N_HARMONICS; h++) {
			harmonic[h].set(frequency * (h + 1));
		}
	}
	
	void morph(param morphAmount, HarmonicTable& A, HarmonicTable& B) {
        for (int h = 0; h < N_HARMONICS; h++) {
            gain[h] = A.amplitude[h] * (1.0 - morphAmount) + B.amplitude[h] * morphAmount;
        }
    }
	
	void process() {
    	for (int h = 0; h < N_HARMONICS; h++)
        	out += (harmonic[h] * gain[h]);
        	
        out *= 0.1;  // static output gain (headroom margin)
    }
};

struct Chroma : Synth {
Flanger flanger;

	struct ChromaNote : public Note {
		ChromaOsc osc;
        ADSR adsr, mod;
        LFO lfo;

		event on(Pitch pitch, Amplitude velocity) {
			const param f = pitch -> Frequency;
			osc.set(f);
			adsr(controls[27], controls[27] + controls[28], controls[29], controls[30]);
			mod(controls[31], controls[31] + controls[32], controls[33], controls[34]);
		}

		event off(Amplitude velocity) {
			adsr.release();
		}

		void process() {
			
			// ** LFO.set **
			lfo.set(controls[35] * 8, controls[36] * 2);
			
			// ** MORPH TABLES **
			int morph = controls[2];
			if (morph)
				osc.morph(controls[3] * lfo, tableA, tableB);
			if (!morph)
				osc.morph(controls[3] * mod, tableA, tableB);
			
			osc * adsr >> out;
			
			if (adsr.finished())
				stop();
		}
	};
	
	void process(){
		// ** SELECT / EDIT OSCILLATOR TABLE **
		int select = controls[0];  // 0 = tableA, 1 = tableB
		int edit = controls[1];
		for (int h = 0; h < N_HARMONICS; h++) {
			if (!edit) {
				select ? tableA.amplitude[h] >> controls[h + 4] : tableB.amplitude[h] >> controls[h + 4];
			} else {
				if (select) {
					tableA.amplitude[h] = controls[h + 4];
				} else {
					tableB.amplitude[h] = controls[h + 4];
				}
			}	
		}
		
		// ** MIXER **
		signal wet = in;
		
		flanger.set(controls[41], controls[42] / 1000.f);
		int flange = controls[40];
		if (flange)
			wet * 0.7 >> flanger >> wet;
			
		// ** OUT **
		( wet * controls[49] + in * (1 - controls[49]) ) * controls[50] >> out;
	}

	Chroma() {
		controls = {
			/* OSCILLATOR */											 //    OSCILLATOR
                Menu   ("HARMONICS", { 15, 25, 45, 18 }, "A", "B"),  	 // 00 ├ HARMONIC TABLES
                Toggle ("E", 0, { 66, 25, 18, 18 }),    			 	 // 01 │
                Menu   ("MORPH", { 15, 65, 45, 18 }, "ENV", "LFO"),  	 // 02 │
                Dial   ("", 0, 1, 0, { 66, 65, 18, 18 }),            	 // 03 │									
                Slider ("1",  0, 1, 0, { 90,  25, 10, 60 }),	     	 // 04 ├ HARMONICS' AMPLITUDE
                Slider ("2",  0, 1, 0, { 105, 25, 10, 60 }),	     	 // 05 │
                Slider ("3",  0, 1, 0, { 120, 25, 10, 60 }),	  	 	 // 06 │
                Slider ("4",  0, 1, 0, { 135, 25, 10, 60 }),	  	 	 // 07 │
                Slider ("5",  0, 1, 0, { 150, 25, 10, 60 }),	  	 	 // 08 │
                Slider ("6",  0, 1, 0, { 165, 25, 10, 60 }),	  	 	 // 09 │
                Slider ("7",  0, 1, 0, { 180, 25, 10, 60 }),	  	 	 // 10 │
                Slider ("8",  0, 1, 0, { 195, 25, 10, 60 }),	  	 	 // 11 │
                Slider ("9",  0, 1, 0, { 210, 25, 10, 60 }),	  	 	 // 12 │
                Slider ("10", 0, 1, 0, { 225, 25, 10, 60 }),	  	 	 // 13 │
                Slider ("11", 0, 1, 0, { 240, 25, 10, 60 }),	  	 	 // 14 │
                Slider ("12", 0, 1, 0, { 255, 25, 10, 60 }),	  	 	 // 15 │
                Slider ("13", 0, 1, 0, { 270, 25, 10, 60 }),	  	 	 // 16 │
                Slider ("14", 0, 1, 0, { 285, 25, 10, 60 }),	  	 	 // 17 │
                Slider ("15", 0, 1, 0, { 300, 25, 10, 60 }),	  	 	 // 18 │
                Slider ("16", 0, 1, 0, { 315, 25, 10, 60 }),   	     	 // 19 └
					   	
			{ "FILTER",												 	 //    FILTER
                Toggle ("HP", 0, { 341, 30, 18, 18 }),               	 // 20 │
                Toggle ("LP", 0, { 367, 30, 18, 18 }),               	 // 21 │
                Menu   ("MOD", { 340, 70, 45, 18 }, "ENV", "LFO"),		 // 22 │
                Dial   ("CUTOFF", 0, 1, 0, { 340, 110, 40, 40 }),    	 // 23 │
                Dial   ("",       0, 1, 0, { 369, 104, 18, 18 }),    	 // 24 │
                Dial   ("Q",      0, 1, 0, { 340, 170, 40, 40 }),    	 // 25 │
                Dial   ("",       0, 1, 0, { 369, 164, 18, 18 }),    	 // 26 └ 
            },  
                          
			{ "AMP ENVELOPE   /   MOD ENVELOPE",						 //    ENVELOPES
                Dial   ("ATTACK",  0.1, 1, 0, { 15,  130, 40, 40 }),	 // 27 ├ AMP
                Dial   ("DECAY",   0.0, 1, 0.5, { 65,  130, 40, 40 }),	 // 28 │ │
                Dial   ("SUSTAIN", 0, 1, 0.75, { 115, 130, 40, 40 }),	 // 29 │ │
                Dial   ("RELEASE", 0, 1, 0.5, { 165, 130, 40, 40 }),   	 // 30 │ └
                Dial   ("", 0, 1, 0, { 44,  124, 18, 18 }),          	 // 31 └ MOD
                Dial   ("", 0, 1, 0, { 94, 124, 18, 18 }),        	 	 // 32   │
                Dial   ("", 0, 1, 0, { 144, 124, 18, 18 }),          	 // 33   │
                Dial   ("", 0, 1, 0, { 194, 124, 18, 18 }) 			 	 // 34   └
            },     	 
			
			{ "LFO",
                Dial   ("RATE",  0, 1, 0, { 231, 130, 40, 40 }),     	 // 35 LFO
                Dial   ("SHAPE", 0, 1, 0, { 281, 130, 40, 40 })      	 // 36 └
            },   
					
			/* MIXER */													 //    EFFECTS
                Toggle ("VIBRATO", 0, { 15, 185, 40, 18 }),          	 // 37 ├ VIBRATO
                Dial   ("", 0, 1, 0, { 65, 185, 18, 18 }),			 	 // 38 │
                Dial   ("", 0, 1, 0, { 88, 185, 18, 18 }),			 	 // 39 │
                Toggle ("FLANGER", 0, { 15, 210, 40, 18 }),			 	 // 40 ├ FLANGER
                Dial   ("", 0.1, 1, 0, { 65, 210, 18, 18 }),			 // 41 │
                Dial   ("", 0.1, 5, 0, { 88, 210, 18, 18 }),			 // 42 │
                Toggle ("CHORUS", 0, { 115, 185, 40, 18 }),			 	 // 43 ├ CHORUS
                Dial   ("", 0, 1, 0, { 165, 185, 18, 18 }),			 	 // 44 │
                Dial   ("", 0, 1, 0, { 188, 185, 18, 18 }),			 	 // 45 │
                Toggle ("DELAY", 0, { 115, 210, 40, 18 }),			 	 // 46 ├ DELAY
                Dial   ("", 0, 1, 0, { 165, 210, 18, 18 }),			 	 // 47 │
                Dial   ("", 0, 1, 0, { 188, 210, 18, 18 }),			 	 // 48 │
                Dial   ("FX", 0, 1, 0, { 239, 205, 24, 23 }),		 	 // 49 └
                Dial   ("VOLUME", 0, 1.5, 1, { 289, 205, 24, 23 })	 	 // 50 OUT
		};
		
		presets = {
			{ "Preset 1", { 0, 0, 0, 0.725, 0.924, 0.000, 0.814, 0.000, 0.637, 0.000, 0.526, 0.000, 0.432, 0.000, 0.000, 0.673, 0.657, 0.000, 0.000, 1.000, 1, 1, 0.000, 0.000, 0.000, 0.000, 0, 0.100, 0.500, 1.000, 0.500, 0.000, 0.000, 0.000, 0.000, 0.502, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 0.000, 0.762 } },
		};
		notes.add<ChromaNote>(32);
	}
};