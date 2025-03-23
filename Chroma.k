
#include <klang.h>
using namespace klang::optimised;

signal cubed(signal x) {
    return x * x * x;
}

signal nonlinear(signal x) {
    return pow(10, 2 * (x - 1));
}

param linearMap(param x, int min, int max) {
	return x * (max - min) + min;
}

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
        lfo = (1.0 - blend1) * sinMod + (blend1 - blend2) * triMod + blend2 * pseudoSaw;
	}
	
	void process() {
		lfo >> out;
	}
};

struct CCF : Effect {
	HPF hpf;
	LPF lpf;
	BPF bpf;
	
	param f = 0;
	param q = 0;
	
	int mode = 0; // 0 = off, 1 = HPF, 2 = LPF, 3 = BPF
	
	void set(param frequency, param resonance, int hp, int lp) {
		f = linearMap(cubed(frequency), 100, 10000);
		if (f > 14000)
            f = 14000;
        if (f < 20)
            f = 20;
            
		q = resonance;
		if (q > 2)
            q = 2;
        if (q < 0)
            q = 0;
		
        if (hp && !lp)       // HPF
            mode = 1;  
        else if (!hp && lp)  // LPF
            mode = 2;  
        else if (hp && lp)   // BPF
            mode = 3;  
        else 			     // bypass
            mode = 0;  
	}
	
	void process() {
        if (mode == 1)
            in >> hpf(f, q) >> out;
        else if (mode == 2)
            in >> lpf(f, q) >> out;
        else if (mode == 3)
            in >> bpf(f, q) >> out;
        else
            in >> out;
	}
};

struct Vibrato : Stereo::Effect {
};

struct Flanger : Stereo::Effect {
	Stereo::Delay<192000> delay;
	Triangle lfo;
	signal mod;
	
	void set(param rate, param depth) {
		mod = lfo(rate) * depth + depth;
	}

	void process() {	
		in + (in >> delay)(mod * fs) >> out;
	}
};

struct Glimmer : Stereo::Effect {  //
Delay<192000> gleam[4];
Sine gleamMod[2];
param a;
param spread;

	signal tap(Delay<192000>& buffer, signal x, param time, param gain) {
		x >> buffer;
		return x + buffer(time * fs) * gain;
	}
	
	void set(param amount) {
		a = amount * 0.5;
		spread = 0.3 + (amount * 0.8);
	}
	
	void process() {
		// LFO modulations
		signal mod1 = gleamMod[0](a * 2, 0);
		signal mod2 = gleamMod[1](a * 2, 0.25);
		
		// short delays with phase inversion
		signal left  = tap(gleam[0], in.l, (0.04 * spread) + mod1, a * 0.75)
                     - tap(gleam[1], in.r, (0.05 * spread) + mod2, a * 0.75);
        signal right = tap(gleam[2], in.r, (0.03 * spread) + mod1, a * 0.75)
                     - tap(gleam[3], in.l, (0.06 * spread) + mod2, a * 0.75);
                     
        in.l + left >> out.l;
        in.r + right >> out.r;
	}
};

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

struct Chroma : Stereo::Synth {
Flanger flanger;
Glimmer glimmer;
Stereo::Delay<192000> pingPong;

	struct ChromaNote : public Mono::Note {
		ChromaOsc osc;
        ADSR adsr, mod;
        LFO lfo;
        CCF filter;

		event on(Pitch pitch, Amplitude velocity) {
			const param f = pitch -> Frequency;
			osc.set(f);
			adsr(controls[27] + 0.005, controls[27] + controls[28], controls[29], controls[30]);
			mod (controls[31] + 0.005, controls[31] + controls[32], controls[33], controls[34]);
		}

		event off(Amplitude velocity) {
			adsr.release();
		}

		void process() {
			// ** MORPH TABLES **
			int morph = controls[2];
			if (morph)
				osc.morph(lfo * controls[3], tableA, tableB);
			if (!morph)
				osc.morph(mod * controls[3], tableA, tableB);
				
			// ** LFO.set **
			lfo.set(controls[35] * 8, controls[36] * 2);
				
			// ** FILTER **
			int filterMod = controls[22];
			param cutoff = controls[23];
			param q = linearMap(controls[25], 0, 2);
			if (filterMod)
				filter.set(cutoff + lfo * controls[24], q + lfo * controls[26], controls[20], controls[21]);
			
			if (!filterMod)
				filter.set(cutoff + mod * controls[24], q + mod * controls[26], controls[20], controls[21]);
			
			osc * adsr >> filter >> out;
			
			if (adsr.finished())
				stop();
		}
	};
	
	void process(){
		// ** EDIT HARMONIC TABLES **
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

		// ** EFFECTS **
		stereo::signal wet = in;
		
		// ** FLANGER
		int flange = controls[37];
		flanger.set(controls[38], controls[39] / 1000.f);
		if (flange)
			wet * 0.75 >> flanger >> wet;
			
		// ** GLIMMER **
		int gleam = controls[40];
		glimmer.set(controls[41]);
		if (gleam) {
			wet * 0.75 >> glimmer >> wet;
		}
			
		// ** DELAY **
		int delay = controls[42];
		stereo::signal time = { controls[43], controls[44] };
		stereo::signal gain = { controls[45], controls[45] };
		param amount = controls[46] * 0.8;
		if (delay) {
			wet + pingPong(time * fs) * gain * amount >> wet;
			pingPong.l << wet.r;
			pingPong.r << wet.l;
		}
		
		// ** OUT **
		param mix = controls[47];
		param volume = controls[48];
		(wet * mix + in * (1 - mix)) * volume >> out;
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
                Dial   ("CUTOFF", 0, 1, 0, { 340, 110, 40, 40 }),  		 // 23 │
                Dial   ("",       -1, 1, 0, { 369, 104, 18, 18 }),    	 // 24 │
                Dial   ("Q",      0, 1, 0, { 340, 170, 40, 40 }),    	 // 25 │
                Dial   ("",       -1, 1, 0, { 369, 164, 18, 18 }),    	 // 26 └ 
            },  
                          
			{ "AMP   /   MOD",						 					 //    ENVELOPES
                Dial   ("ATTACK",  0, 1, 0, { 15,  130, 40, 40 }),	 	 // 27 ├ AMP
                Dial   ("DECAY",   0.0, 1, 0.5, { 65,  130, 40, 40 }),	 // 28 │ │
                Dial   ("SUSTAIN", 0, 1, 0.75, { 115, 130, 40, 40 }),	 // 29 │ │
                Dial   ("RELEASE", 0, 1, 0.5, { 165, 130, 40, 40 }),   	 // 30 │ └
                Dial   ("", 0, 1, 0, { 44,  124, 18, 18 }),          	 // 31 └ MOD
                Dial   ("", 0.0, 1, 0, { 94, 124, 18, 18 }),        	 // 32   │
                Dial   ("", 0, 1, 0, { 144, 124, 18, 18 }),          	 // 33   │
                Dial   ("", 0, 1, 0, { 194, 124, 18, 18 }) 			 	 // 34   └
            },     	 
			
			{ "LFO",
                Dial   ("RATE",  0, 1, 0, { 231, 130, 40, 40 }),     	 // 35 LFO
                Dial   ("SHAPE", 0, 1, 0, { 281, 130, 40, 40 })      	 // 36 └
            },   
					
			/* MIXER */													 //    EFFECTS
                Toggle ("FLANGER", 0, { 15, 185, 40, 18 }),          	 // 37 ├ FLANGER
                Dial   ("", 0.1, 1, 0, { 65, 185, 18, 18 }),			 // 38 │
                Dial   ("", 0.1, 5, 0, { 88, 185, 18, 18 }),			 // 39 │
                Toggle ("GLIMMER", 0, { 15, 210, 40, 18 }),			 	 // 40 ├ GLIMMER CHORUS
                Dial   ("", 0.1, 1, 0, { 65, 210, 18, 18 }),			 // 41 │
                Toggle ("DELAY", 0, { 115, 185, 40, 18 }),			 	 // 42 ├ DELAY
                Dial   ("", 0, 1, 0, { 165, 185, 18, 18 }),			 	 // 43 │
                Dial   ("", 0, 1, 0, { 188, 185, 18, 18 }),			 	 // 44 │
                Dial   ("", 0, 1, 0, { 165, 210, 18, 18 }),			 	 // 45 │
                Dial   ("", 0, 1, 0, { 188, 210, 18, 18 }),			 	 // 46 │
                Dial   ("FX", 0, 1, 0, { 239, 205, 24, 23 }),		 	 // 47 └
                Dial   ("VOLUME", 0, 1.5, 1, { 289, 205, 24, 23 })	 	 // 48 OUT
		};
		
		presets = {
			{ "Preset 1", { 0, 0, 0, 0.725, 0.924, 0.000, 0.814, 0.000, 0.637, 0.000, 0.526, 0.000, 0.432, 0.000, 0.000, 0.673, 0.657, 0.000, 0.000, 1.000, 1, 1, 0.000, 0.000, 0.000, 0.000, 0, 0.100, 0.500, 1.000, 0.500, 0.000, 0.000, 0.000, 0.000, 0.502, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 1, 0.000, 0.000, 0.000, 0.762 } },
			{ "Double Attack", { 1, 1, 1, 1.000, 1.000, 0.591, 0.600, 0.000, 0.000, 0.000, 0.200, 0.700, 0.100, 0.080, 0.070, 0.050, 0.040, 0.030, 0.020, 0.010, 0, 1, 0, 0.218, 0.818, 0.000, 0.308, 0.000, 0.348, 0.402, 0.207, 0.000, 0.200, 0.000, 0.000, 1.000, 1.000, 1, 0.447, 1.043, 1, 0.631, 0, 0.309, 0.310, 0.383, 1.000, 1.000, 1.000 } },
		};
		notes.add<ChromaNote>(32);
	}
};