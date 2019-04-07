( // 1. start server, load samples, initialize buses
s.waitForBoot({
	MIDIIn.connectAll;

	~beat1 = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "boly.wav", action: "beat1 loaded".postln);
	~beat2 = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "symbols.wav", action: "beat2 loaded".postln);

	~drumBus = Bus.audio(s);
	~padRand = Bus.control(s);
	~padAmp = Bus.control(s);
});
)

( // 2. define synths and sequences
SynthDef(\kick, { |out = 0, freq0 = 220.0, freq1 = 110.0, bendTime = 0.25, decay = 0.5, amp = 0.4|
	var freq_env, sine, amp_env, sig;
	freq_env = EnvGen.ar(Env.new([freq0, freq1], [bendTime], curve: \exp));
	sine = SinOsc.ar(freq_env, 0, amp);
	amp_env = EnvGen.ar(Env.perc(0.001, decay), doneAction: Done.freeSelf);
    sig = sine * amp_env;
    Out.ar(out, sig);
}).add;
SynthDef(\snare, { |out = 0, decay = 1.0, amp = 0.4|
	var noise, freq_env, sine, amp_env, sig;
	noise = PinkNoise.ar(amp);
	freq_env = EnvGen.ar(Env.new([200.0, 20.0], [0.1], curve: \exp));
	sine = SinOsc.ar(freq_env);
	amp_env = EnvGen.ar(Env.perc(0.001, decay), doneAction: Done.freeSelf);
	sig = HPF.ar(noise + sine, 400.0) * amp_env;
	Out.ar(out, sig);
}).add;
SynthDef(\hat, { |out = 0, decay = 1.0, amp = 0.3|
	var noise, amp_env, sig;
	noise = WhiteNoise.ar(amp);
	amp_env = EnvGen.ar(Env.perc(0.001, decay), doneAction: Done.freeSelf);
	sig = HPF.ar(noise, 16000) * amp_env;
	Out.ar(out, sig);
}).add;
SynthDef(\drums, { |amp = 0.0, envTime = 0.001, delayLen = 0.1, delayAmp = 0.0|
	var src, knee, satanMaximizer, delay;
	src = In.ar(~drumBus);
	knee = -60.0; // [0, -90]
	// https://sccode.org/1-51w
	satanMaximizer = 0.5 * DelayC.ar(src, 0.01, envTime * 0.5) * EnvFollow.ar(src, 1 - (envTime * SampleRate.ir).reciprocal).max(knee).reciprocal;
	delay = DelayC.ar(delayAmp * amp * satanMaximizer, 0.1, delayLen);
	Out.ar(0, (amp*satanMaximizer + delay)!2);
}).add;

SynthDef(\beatcollider, { |cutoff = 20.0, amp = 0.0, rate1 = 0.0, rate2 = 0.0, envTime = 0.001|
	var conv, knee, satanMaximizer, filter, delay, sig;
	conv = Convolution.ar(
		PlayBuf.ar(~beat1.numChannels, ~beat1, rate: rate1, loop: 1.0),
		PlayBuf.ar(~beat2.numChannels, ~beat2, rate: rate2, loop: 1.0),
		framesize: 256
	);
	knee = -90.0; // [0, -90]
	// https://sccode.org/1-51w
	satanMaximizer = amp * DelayC.ar(conv, 0.01, envTime * 0.5) * EnvFollow.ar(conv, 1 - (envTime * SampleRate.ir).reciprocal).max(knee).reciprocal;
	filter = LPFVS6.ar(satanMaximizer, cutoff, 0.999999);
	delay = DelayN.ar(filter, 2.0, 0.1);
	sig = filter + 0.7*delay;
	Out.ar(0, sig);
}).add;

SynthDef(\pad, { |freq = 440.0, amp = 0.4, attack = 0.3, decay = 0.3, kRand = 0.0|
	var sig;
    sig = Mix.fill(4, { |i|
		var doneAction, attack1, decay1, preAttack, postDecay, ampEnv, kFreqRand, freqRand, sine;
		doneAction = Done.none;
		if(i == 0) {
			doneAction = Done.freeSelf;
		};
		attack1 = attack/(i+1);
		decay1 = decay/(i+1);
		preAttack = attack - attack1;
		postDecay = decay - decay1;
		ampEnv = amp/(i+1) * EnvGen.ar(Env.new([0.0, 0.0, 1.0, 0.0, 0.0], [preAttack, attack1, decay1, postDecay]), doneAction: doneAction);
		kFreqRand = 1 + kRand;
		freqRand = ExpRand(kFreqRand.reciprocal, kFreqRand);
		sine = SinOsc.ar((i+1)*freq * freqRand, 0);
		sine * ampEnv;
	});
	Out.ar(0, HPF.ar(sig, 250.0)!2);
}).add;

~drumClock = TempoClock.new(60.0 / 60.0);

~kick_seq = Task({
	var delta, rootNote, freq, bendTime, decay, offsets, noteOffset;
	rootNote = 38;
	bendTime = 0.09;
	decay = 1.4;
	offsets = [-1, -4, -5];
	loop {
		delta = rrand(1, 15) / 4.0;
		noteOffset = offsets[rrand(0, offsets.size-1)];
		freq = (rootNote+noteOffset).midicps;
		Synth(\kick, [out: ~drumBus, freq0: freq*4.0, freq1: freq, bendTime: bendTime, decay: decay]);
		delta.wait;
		noteOffset = offsets[rrand(0, offsets.size-1)];
		freq = (rootNote+noteOffset).midicps;
		Synth(\kick, [out: ~drumBus, freq0: freq*4.0, freq1: freq, bendTime: bendTime, decay: decay]);
		(4-delta).wait;
	}
});
~hat_seq = Task({
	var amp1, amp2, amp3, i;
	amp1 = 0.3;
	amp2 = 0.3;
	amp3 = 0.7;
	i = 0;
	loop {
		var choice;
		if(i == 0) {
			Synth(\hat, [out: ~drumBus, decay: 2.0, amp: amp1]);
		};
		choice = rrand(0, 3);
		0.25.wait;
		if((choice == 1) || (choice == 3)) {
			Synth(\hat, [out: ~drumBus, decay: 0.1, amp: amp2]);
		};
		0.25.wait;
		Synth(\hat, [out: ~drumBus, decay: 0.2, amp: amp3]);
		0.25.wait;
		if((choice == 2) || (choice == 3)) {
			Synth(\hat, [out: ~drumBus, decay: 0.1, amp: amp2]);
		};
		0.25.wait;
		i = (i+1)%8;
	}
});
~snare_seq = Task({
	loop {
		1.0.wait;
		Synth(\snare, [out: ~drumBus, decay: 0.15, amp: 0.6]);
		1.0.wait;
	}
});
~tempo_seq = Task({
	loop {
		var tempo;
		tempo = exprand(32.0, 512.0);
		~drumClock.tempo = tempo / 60.0;
		(1.0/8.0).wait;
	}
});

~pad_seq = Task({
	var rootNote, intervals, mMax, note, freq;
	rootNote = 38;
	intervals = [-5, -4, -1, 0, 1, 4, 5];
	mMax = 1;
	loop {
		note = rootNote + (intervals.choose * rrand(1, mMax));
		~padRand.get({ |kRand| ~padAmp.get({ |amp|
			Synth(\pad, [freq: note.midicps, attack: 2.0, decay: 2.0, amp: amp, kRand: kRand]);
		})});
		exprand(1.0, 2.0).wait;
	}
});
)

( // 3. start playback and configure MIDI input
~beatcollider = Synth(\beatcollider, [cutoff: 20.0, amp: 0.0, rate1: 0.0, rate2: 0.0, envTime: 0.01]);
~drums = Synth(\drums, [amp: 0.0, envTime: 0.01]);
[~kick_seq, ~hat_seq, ~snare_seq, ~tempo_seq].do({ |seq| seq.reset; seq.play(~drumClock, quant: 1.0); });
~pad_seq.play;

// left pad y
MIDIdef.cc(\cc30, { |val, num, chan, src| ~beatcollider.set(\rate1, val.linlin(0.0, 127.0, -2.0, 2.0)); }, 30);
// left pad x
MIDIdef.cc(\cc31, { |val, num, chan, src| ~beatcollider.set(\rate2, val.linlin(0.0, 127.0, -2.0, 2.0)); }, 31);
// left slider 1
MIDIdef.cc(\cc32, { |val, num, chan, src|
	~beatcollider.set(\cutoff, val.linexp(0.0, 127.0, 20.0, 22000.0));
	~beatcollider.set(\amp, 0.2 * val.linlin(0.0, 127.0, 0.0, 1.0).pow(0.9));
}, 32);
// left slider 2
MIDIdef.cc(\cc33, { |val, num, chan, src| ~beatcollider.set(\envTime, val.linexp(0.0, 127.0, 0.01, 0.00003)); }, 33);

// middle pad y
MIDIdef.cc(\cc34, { |val, num, chan, src| ~drums.set(\delayAmp, val.linlin(0.0, 127.0, 0.0, 1.0)); }, 34);
// middle pad x
MIDIdef.cc(\cc35, { |val, num, chan, src| ~drums.set(\delayLen, val.linexp(0.0, 127.0, 0.01, 0.03)); }, 35);
// middle slider 1
MIDIdef.cc(\cc36, { |val, num, chan, src| ~drums.set(\amp, 0.5*val.linlin(0.0, 127.0, 0.0, 1.0).pow(2.0)); }, 36);
// middle slider 2
MIDIdef.cc(\cc37, { |val, num, chan, src| ~drums.set(\envTime, val.linexp(0.0, 127.0, 0.01, 0.0003)); }, 37);

// right pad y
//MIDIdef.cc(\cc38, { |val, num, chan, src| ~drums.set(\delayAmp, val.linlin(0.0, 127.0, 0.0, 1.0)); }, 38);
// right pad x
//MIDIdef.cc(\cc39, { |val, num, chan, src| ~drums.set(\delayLen, val.linexp(0.0, 127.0, 0.01, 0.03)); }, 39);
// right slider 1
MIDIdef.cc(\cc40, { |val, num, chan, src| ~padAmp.set(0.6*val.linlin(0.0, 127.0, 0.0, 1.0).pow(2.0)); }, 40);
// right slider 2
MIDIdef.cc(\cc41, { |val, num, chan, src| ~padRand.set(val.linexp(0.0, 127.0, 0.01, 0.5)); }, 41);
)

s.record(thisProcess.nowExecutingPath.dirname +/+ "recording.wav", numChannels: 2);
s.stopRecording;