public class NativeSoundPlayer extends Thread{
  private Music musicInstance;
  private SourceDataLine line;
  private boolean finished=false;
  private byte[] internalBuffer;
  private int intBufSamples;
  private int extBufSamples;
  private AudioFormat format;
  private ByteArrayOutputStream recordBuffer;
  private File recordFile;
  private boolean doRecord=false;
  public NativeSoundPlayer(Music mus,int sampleRate,File recFile){
    recordFile=recFile;
    if(recordFile!=null) doRecord=true;
    extBufSamples=sampleRate/2; // 500ms/25frame buffer
    intBufSamples=sampleRate/5; // 200ms/10frame chunk size
    internalBuffer=new byte[intBufSamples*2*2];
    musicInstance=mus;
    musicInstance.initSampleRate(sampleRate);
    try{
      format = new AudioFormat((float)sampleRate, 8*2, 2, true, false);
      line = (SourceDataLine) AudioSystem.getSourceDataLine(format);
      line.open(format, extBufSamples*2*2);
    }catch(LineUnavailableException e){
      println_error("Couldn't get audio output!");
      finished=true;
      return;
    }
  }
  public void open(){
    if(finished) return;
    if(doRecord){
      recordBuffer = new ByteArrayOutputStream();
      println_info("Beginning soundtrack recording");
    }
    start();
    println_debug("Audio output started");
  }
  public void close(){
    if(finished) return;
    finished=true;
    if(recordFile!=null){
      println_debug("Saving soundtrack recording...");
      ByteArrayInputStream b_in = new ByteArrayInputStream(recordBuffer.toByteArray());
      AudioInputStream ais = new AudioInputStream(b_in, format, recordBuffer.size());
      try{
        AudioSystem.write(ais, AudioFileFormat.Type.WAVE, recordFile);
      }catch(IOException e){
        println_info("Couldn't write to file "+recordFile.getAbsolutePath());
      }
    }
    println_debug("Audio output finished");
  }
  public void run(){
    if(finished) return;
    line.start();
    while(!finished){
      int offset = 0;
      // Generate sample buffer
      for(int i = 0; i < intBufSamples; i++){
        short sampleL = (short)(int)min(max(-32768, round(32767 * musicInstance.makeOutputSample())), 32767);
        short sampleR = sampleL;
        internalBuffer[offset++] = (byte)(sampleL >> 0);
        internalBuffer[offset++] = (byte)(sampleL >> 8);
        internalBuffer[offset++] = (byte)(sampleR >> 0);
        internalBuffer[offset++] = (byte)(sampleR >> 8);
      }
      // Copy internal buffer to record buffer
      if(doRecord) {
        recordBuffer.write(internalBuffer, 0, internalBuffer.length);
      }
      // Wait for space to become available
      while(line.available() < intBufSamples << 2){
        try {Thread.sleep(1);}
        catch (InterruptedException nom){}
      }
      line.write(internalBuffer, 0, internalBuffer.length);
    }
    line.flush();
    line.stop();
    line.close();
    line = null;
  }
}

public class Music {
  // HQ Mode gains for Triwave, Pulse1, Pulse2, Noise, and Output mix.
  // Carefully obtained to achieve roughly the same perceived loudness on each channel as non-HQ mode
  // Output mix gain is NOT applied to audio data fed to visual effects!
  float[] hqGains={1.06f,1.19f,1.00f,1.00f,1.00f};//{1,1,1,1,1};
  int songSpeed; // Frames per track line
  int trackSize; // Length of one track
  int lastWholeSample=0; // Gensample index
  float sampleFract=0; // Fractional part of gensample index
  float sampleDelta=1; // Change in sample index at gensample rate for each outsample
  float output=0; // Audio output buffer
  int currentFrame=0; // Current video frame (field) for timing generation
  int sampleInCurrentFrame=0; // One sample per scanline
  int trackTimer=0; // Time in frames until track line advances
  int currentTrackLine; // Track line index
  int currentSongLine; // Song line index
  Song song; // Song object
  boolean songFinished=false; // Finished flag
  OutputFilter outFilter=new OutputFilter(); // Filter effect (used only when high quality mode is off)
  MathTables mathTables;
  boolean highQuality;
  boolean filtered;
  ConcurrentLinkedQueue<AudioFrameBuffer> afbArray=new ConcurrentLinkedQueue<AudioFrameBuffer>();
  AudioFrameBuffer workingAfb=new AudioFrameBuffer();
  int amplitudeNow;
  boolean playing=false;
  float sampleRate;
  
  boolean[] mutedChannels=new boolean[4]; //0=Tri wave, 1=Filt pulse, 2=Raw pulse, 3=Noise (pseudo-channel)

  int[] c_inst=new int[3];
  int[] c_instLine=new int[3];
  int[] c_pw=new int[3];
  int[] c_ivolume=new int[3];
  int[] c_noise=new int[3];
  int[] c_instDelay=new int[3];
  int[] c_vibDepth=new int[3];
  int[] c_vibRate=new int[3];
  int[] c_noteWhole=new int[3];
  int[] c_noteFract=new int[3];
  int[] c_glide=new int[3];
  int[] c_fade=new int[3];
  int[] c_pwDelta=new int[3];
  int[] c_vibPos=new int[3];
  int[] c_transp=new int[3];
  int[] c_track=new int[3];
  int[] c_lasti=new int[3];
  int[] c_freq=new int[3];
  int[] c_phase_hq=new int[3];
  int[] c_phase=new int[3];
  int[] c_volume=new int[3];
  int filtStage1;
  int filtStage2;
  float filtStage1High;
  float filtStage2High;
  int noiseVol;
  int noiseReg;
  int noiseTimerHigh;

  public Music(String[] songStringArray, int trackSize, int songSpeed, MathTables tables) {
    initSilence();
    this.songSpeed=songSpeed;
    this.trackSize=trackSize;
    this.mathTables=tables;
    loadSong(songStringArray);
    // Calculated by rough impedance 1k, C=10uF
    outFilter.setDcRC(0.01); // RC constant for (high pass) DC filter
    // Tweaked by ear and by comparing waveforms to match the original recording
    outFilter.setLpRC(0.00175); // RC constant for implicit low pass filter
    outFilter.setLpFactor(0.9); // How much of the low pass to mix in
    outFilter.setAmplitude(0.875); // How loud to make the final output (roughly match high quality mode)
    afbArray.add(new AudioFrameBuffer());
  }
  public void setHighQuality(boolean hq){
    this.highQuality=hq;
    updateSampleDelta();
  }
  public void setFiltered(boolean filt) {
    this.filtered=filt;
  }
  private void initSampleRate(float sr){
    sampleRate=sr;
    outFilter.setDt(1f/sr);
    updateSampleDelta();
  }
  private void updateSampleDelta(){
    //15625 lines per second, 1 sample per line (4 for high quality mode)
    sampleDelta=(15625f/sampleRate)*(highQuality?4:1);
  }
  public boolean isHighQuality(){
    return highQuality;
  }
  public float makeOutputSample() {
    if(playing){
      sampleFract+=sampleDelta;
      if (sampleFract>=1) { // Fractional part >=1, new gensample!
        int doSamples=floor((float)sampleFract); // How many gensamples
        float doSamplesInv=1f/doSamples;
        sampleFract-=doSamples; // Remove integer part
        output=0;
        amplitudeNow=0;
        for (int i=0; i<doSamples; i++) {
          if ((lastWholeSample&3)==0 || !highQuality) {
            sampleInCurrentFrame++;
            if (sampleInCurrentFrame>=312) {
              // Handle new frame
              currentFrame++;
              sampleInCurrentFrame-=312;
              tick();
              afbArray.add(workingAfb);
              workingAfb=new AudioFrameBuffer();
              workingAfb.frameIndex=currentFrame;
              workingAfb.trackLine=currentTrackLine;
              workingAfb.songLine=currentSongLine;
            }
          }
          output+=getSample();
          lastWholeSample++;
        }
        output*=doSamplesInv;
        amplitudeNow*=doSamplesInv;
      }
      workingAfb.maxAmplitude=max(workingAfb.maxAmplitude, amplitudeNow);
    }
    if(filtered)
      return outFilter.doSample(output); // Output filtered
    else return output; // Output outsample
  }
  public void setChannelMuted(int ch,boolean muted){
    mutedChannels[ch&3]=muted;
  }
  public boolean isChannelMuted(int ch){
    return mutedChannels[ch&3];
  }
  public boolean anyChannelsMuted(){
    return mutedChannels[0] || mutedChannels[1] || mutedChannels[2] || mutedChannels[3];
  }
  public int getCurrentFrame() {
    return currentFrame;
  }
  public void setPlaying(boolean s){
    playing=s;
  }
  public boolean isPlaying(){
    return playing;
  }
  private float getSample() {
    // Update oscillator phase for each channel, taking HQ into account
    int hqRound = highQuality ? 2 : 0; // hq_scale / 2
    int hqShift = highQuality ? 2 : 0; // log2(hq_scale)
    for (int ch=0; ch<3; ch++) {
      c_phase_hq[ch]+=c_freq[ch];
      c_phase_hq[ch]&=highQuality?0x3FFFF:0xFFFF; // Keep in 16bit limit, or 4x for HQ
      c_phase[ch]=(c_phase_hq[ch]+hqRound)>>hqShift; // Round and reduce phase by 4x if HQ
    }
    // Run the noise generator
    noiseTimerHigh++;
    noiseTimerHigh &= highQuality? 3 : 0; // mod (hq_scale - 1)
    if(noiseTimerHigh == 0) {
      boolean noiseCarry=(noiseReg&0x8000)!=0; // Get old MSB
      noiseReg<<=1; // Shift
      boolean noiseNegative=(noiseReg&0x8000)!=0; // Get new MSB
      int nrHigh=noiseReg&0xFF00; // Preserve high byte
      if (noiseCarry!=noiseNegative)noiseReg+=0x33; // Carry XOR negative
      noiseReg&=0xFF; // Keep low byte from addition
      noiseReg|=nrHigh; // Restore high byte
    }
    float retVal=0;
    byte retByte=0;
    if (!highQuality) {
      // Channel 1: Filtered pulse wave
      int wavePulse1=((c_phase[1]>>8)<c_pw[1])?-c_volume[1]:c_volume[1];
      int cutoff=c_pw[0]; // Cutoff is triangle channel's otherwise-unused pulse width
      // 2 pole low-pass filter
      wavePulse1-=filtStage1;
      filtStage1+=(wavePulse1*cutoff)>>8; // 1st stage output
      wavePulse1-=filtStage2;
      filtStage2+=(wavePulse1*cutoff)>>8; 
      int wave=mutedChannels[1]?0:filtStage2; // 2nd stage output
      // Channel 2: Pulse wave
      int wavePulse2=((c_phase[2]>>8)<c_pw[2])?-c_volume[2]:c_volume[2];
      wave+=mutedChannels[2]?0:wavePulse2;
      // Half before adding triangle and noise
      wave>>=1;
      // Channel 0: Triangle wave
      int waveTri=c_phase[0]>>8;
      waveTri=(waveTri>=128)?(255-waveTri):waveTri;
      waveTri-=64;
      waveTri*=c_volume[0];
      waveTri>>=7;
      wave+=mutedChannels[0]?0:waveTri;
      // Add noise
      wave+=mutedChannels[3]?0:(((noiseReg>>15)==1)?-noiseVol:noiseVol);
      // Simulated 6-bit DAC
      int dac = 128+wave;
      dac >>= 2;
      retVal = (dac*(1/64f))-0.5f;
      retByte = byte(wave);
    } else {
      // Channel 1: Filtered pulse wave
      float wavePulse1=(round(c_phase[1]*(1/256f))<c_pw[1])?-c_volume[1]:c_volume[1];
      float cutoff=round(c_pw[0]*0.25f); // Cutoff is triangle channel's otherwise-unused pulse width
      // 2 pole low-pass filter
      wavePulse1-=filtStage1High;
      filtStage1High+=(wavePulse1*cutoff)*(1/256f); // 1st stage output
      wavePulse1-=filtStage2High;
      filtStage2High+=(wavePulse1*cutoff)*(1/256f);
      float wave=mutedChannels[1]?0:filtStage2High*hqGains[0]; // 2nd stage output
      // Channel 2: Pulse wave
      float wavePulse2=(round(c_phase[2]*(1/256f))<c_pw[2])?-c_volume[2]:c_volume[2];
      wave+=mutedChannels[2]?0:wavePulse2*hqGains[1];
      // Channel 0: Triangle wave
      float waveTri=c_phase[0];
      waveTri=(waveTri>=32768f)?(65535f-waveTri):waveTri;
      waveTri-=16384f;
      // Generate some distortion to make the triangle wave less boring
      /*float waveTriDistort=abs(waveTri)*(1/16384f);
      waveTriDistort*=waveTriDistort;
      waveTriDistort=waveTri<0?-waveTriDistort:waveTriDistort; // Preserve sign
      waveTriDistort*=16384f;
      waveTri+=waveTriDistort; // Mix distortion in
      waveTri*=0.5f;*/
      waveTri*=c_volume[0]*(1/32768f)*hqGains[2];
      wave*=0.5f;
      wave+=mutedChannels[0]?0:waveTri;
      wave+=mutedChannels[3]?0:(((noiseReg>>15)==1)?-noiseVol:noiseVol)*hqGains[3]; // Gain to match non-HQ mode
      // No DAC simulation, just scale appropriately.
      float dac = wave*0.25f;
      retVal = hqGains[4]*dac*(1/64f); // Gain to match non-HQ mode
      retByte=byte(wave);
    }
    workingAfb.samples[sampleInCurrentFrame]=retByte;
    amplitudeNow+=abs(retByte);
    return retVal;
  }
  private void tick() {
    if (currentSongLine>=song.length()) return; // Song ended already
    trackTimer--;
    if (trackTimer<0) { // New track line
      currentTrackLine++;
      if (currentTrackLine>=trackSize) { // New song line
        currentTrackLine=0;
        currentSongLine++;
        if (currentSongLine<song.length())
        for (int ch=0; ch<3; ch++) {
          // Update track/transp
          c_track[ch]=song.lines[currentSongLine].order[ch];
          c_transp[ch]=song.lines[currentSongLine].transp[ch];
        }else{ // Song end
          songFinished=true;
          return;
        }
      }
      for (int ch=0; ch<3; ch++) {
        // Load track line
        int note=(song.tracks[c_track[ch]].lines[currentTrackLine].note>>2)&0x3F;
        int inst=song.tracks[c_track[ch]].lines[currentTrackLine].instrument&0x1F;
        if (inst>0) { // Update instrument if there is one
          // Load instrument
          loadInstrument(ch, inst);
          // Preserve instrument if it came with a note
          if (note>0)c_lasti[ch]=inst;
        }
        if (note>0) {
          note+=c_transp[ch]; // Add transpose
          note&=0xFF; // Prevent underflow when note < 16 and transpose < note
          loadInstrument(ch, c_lasti[ch]); // Load last preserved instrument
          // Init channel parameters to defaults
          c_noteWhole[ch]=note;
          c_noteFract[ch]=0;
          c_glide[ch]=0;
          c_fade[ch]=0;
          c_pwDelta[ch]=0;
          c_vibDepth[ch]=0;
          c_ivolume[ch]=48;
          c_vibRate[ch]=15;
        }
      }
      trackTimer=songSpeed-1; // Wait time until next track line
    }
    noiseVol=0; // Silence noise each frame
    for (int ch=0; ch<3; ch++) {
      while (true) {
        int instDelTmp=c_instDelay[ch]-1;
        if (instDelTmp>=0)break; // Waiting?
        if (c_instLine[ch]>=song.instruments[c_inst[ch]].length()) {
          println_error("Instrument "+c_inst[ch]+" went past buffer!");
          println_error("Length: "+song.instruments[c_inst[ch]].length()+", Line: "+c_instLine[ch]);
          break;
        }
        // Load command
        int commandTmp=song.instruments[c_inst[ch]].lines[c_instLine[ch]].command&0xF;
        int paramTmp=song.instruments[c_inst[ch]].lines[c_instLine[ch]].param&0xF;
        boolean flag=false; // Prevent instrument line advancing when it shouldn't
        switch(commandTmp) {
        case 0:
          // Set instrument, don't advance line
          loadInstrument(ch, paramTmp);
          flag=true;
          break;
        case 1:
          // Pulse width * 16
          c_pw[ch]=paramTmp<<4;
          break;
        case 2:
          // Volume * 4
          c_ivolume[ch]=paramTmp<<2;
          break;
        case 3:
          // Noise volume
          c_noise[ch]=paramTmp;
          break;
        case 4:
          // Delay until next instrument line
          c_instDelay[ch]=paramTmp;
          break;
        case 5:
          // Vibrato depth
          c_vibDepth[ch]=paramTmp;
          break;
        case 6:
          // Vibrato rate
          c_vibRate[ch]=paramTmp;
          break;
        case 7:
          // Illegal command, implemented for completeness!
          c_noteFract[ch]=paramTmp;
          break;
        case 8:
        case 9:
          // Relative set note
          c_noteWhole[ch]+=(commandTmp==9)?-paramTmp:paramTmp;
          break;
        case 10:
        case 11:
          // Relative set pitch glide
          c_glide[ch]+=(commandTmp==11)?-paramTmp:paramTmp;
          break;
        case 12:
        case 13:
          // Relative set volume fade
          c_fade[ch]+=(commandTmp==13)?-paramTmp:paramTmp;
          break;
        case 14:
        case 15:
          // Relative set pulse width increase rate
          c_pwDelta[ch]+=(commandTmp==15)?-paramTmp:paramTmp;
          break;
        }
        if (!flag)c_instLine[ch]++;
      }
      c_instDelay[ch]--;
      int noteWhole=c_noteWhole[ch];
      int noteFract=c_noteFract[ch];
      int vx=c_vibDepth[ch];
      vx*=byte(mathTables.sin8(c_vibPos[ch]));
      vx>>=1;
      noteFract+=vx;
      while (noteFract>=256) {
        noteWhole++;
        noteFract-=256;
      }
      while (noteFract<0) {
        noteWhole--;
        noteFract+=256;
      }
      noteWhole&=0xFF;
      c_vibPos[ch]+=c_vibRate[ch]<<1;
      c_vibPos[ch]&=0xFF;
      int octave = 6;
      while (true) {
        octave--;
        noteWhole-=12;
        if (noteWhole<=0)break;
      }
      noteWhole+=12;
      noteWhole&=0xFF;
      noteFract&=0xFF;
      int freq=mathTables.freq(noteWhole);
      int dist=mathTables.freq(noteWhole+1)-freq;
      while (true) {
        octave--;
        if (octave<0)break;
        freq>>=1;
        dist>>=1;
      }
      freq+=(dist*noteFract)>>8;
      noteWhole=c_noteWhole[ch];
      noteFract=c_noteFract[ch];
      noteFract+=c_glide[ch]<<4;
      while (noteFract>=256) {
        noteWhole++;
        noteFract-=256;
      }
      while (noteFract<0) {
        noteWhole--;
        noteFract+=256;
      }
      if (noteWhole<=0) {
        noteWhole=0;
        noteFract=0;
      }
      c_noteWhole[ch]=noteWhole;
      c_noteFract[ch]=noteFract;
      c_ivolume[ch]+=c_fade[ch];
      if (c_ivolume[ch]<0)c_ivolume[ch]=0;
      if (c_ivolume[ch]>63)c_ivolume[ch]=63;
      c_pw[ch]+=c_pwDelta[ch];
      c_pw[ch]&=0xFF;
      if (c_pw[ch]>=244)c_pw[ch]-=232;
      noiseVol+=c_noise[ch];
      if (c_noise[ch]>0)c_noise[ch]--;
      c_freq[ch]=freq;
      c_volume[ch]=c_ivolume[ch];
    }
  }
  public AudioFrameBuffer getNextAfb(int frame) {
    AudioFrameBuffer afb=null;
    while (!afbArray.isEmpty()) {
      afb=afbArray.poll();
      if (afb.frameIndex>=frame)break;
    }
    return afb;
  }
  private void loadInstrument(int channel, int instrument) {
    c_inst[channel]=instrument;
    c_instLine[channel]=0;
    c_instDelay[channel]=0;
  }
  private void loadSong(String[] lines) {
    // Force stop playing
    playing=false;
    initSilence();
    if (lines.length==0) {
      println_warn("Song empty!");
      return;
    }
    ArrayList<int[]> sl=new ArrayList<int[]>();
    ArrayList<int[]> tl=new ArrayList<int[]>();
    ArrayList<int[]> il=new ArrayList<int[]>();
    boolean inSongData=false;
    String songTitle="";
    for (String line : lines) {
      // Strip any line breaks
      line.replaceAll("\n","");
      line.replaceAll("\r","");
      if (line.startsWith("sl ")) {
        inSongData=true;
        String[] parts = line.split(" ");
        if (parts.length == 8) {
          try {
            int[] l=new int[7];
            for (int i=0; i<7; i++)l[i]=Integer.parseInt(parts[i+1], 16);
            sl.add(l);
          }
          catch(NumberFormatException e) {
            continue;
          }
        }
      } else if (line.startsWith("tl ")) {
        inSongData=true;
        String[] parts = line.split(" ");
        if (parts.length == 5) {
          try {
            int[] l=new int[4];
            for (int i=0; i<4; i++)l[i]=Integer.parseInt(parts[i+1], 16);
            tl.add(l);
          }
          catch(NumberFormatException e) {
            continue;
          }
        }
      } else if (line.startsWith("il ")) {
        inSongData=true;
        String[] parts = line.split(" ");
        if (parts.length == 4) {
          try {
            int[] l=new int[3];
            for (int i=0; i<3; i++)l[i]=Integer.parseInt(parts[i+1], 16);
            il.add(l);
          }
          catch(NumberFormatException e) {
            continue;
          }
        }
      } else if(!inSongData) { // There may be comments between data lines that we don't want to print!
        println_any(line);
        if(songTitle.length()==0)songTitle=line;
      }
    }
    int maxSl=0;
    for (int[] line : sl) {
      maxSl=max(maxSl, line[0]+1);
    }
    int overflowSl=max(0,maxSl-256);
    song=new Song(maxSl);
    for (int[] line : sl) {
      song.lines[line[0]].order[0]=line[1]&0xFF;
      song.lines[line[0]].order[1]=line[3]&0xFF;
      song.lines[line[0]].order[2]=line[5]&0xFF;
      song.lines[line[0]].transp[0]=(byte)line[2];
      song.lines[line[0]].transp[1]=(byte)line[4];
      song.lines[line[0]].transp[2]=(byte)line[6];
    }
    int maxTl=0;
    for (int[] line : tl) {
      maxTl=max(maxTl, line[0]+1);
    }
    int overflowTl=max(0,maxTl-256);
    song.tracks=new Track[maxTl];
    for (int i=0; i<maxTl; i++)song.tracks[i]=new Track(trackSize);
    for (int[] line : tl) {
      if (line[1]>=trackSize)continue;
      song.tracks[line[0]].lines[line[1]].note=line[2];
      song.tracks[line[0]].lines[line[1]].instrument=line[3];
    }
    for (Track t : song.tracks) {
      int lasti=255;
      for (int i=0; i<trackSize; i++) {
        if (t.lines[i].note>0 && t.lines[i].instrument>0) {
          if (t.lines[i].instrument==lasti)t.lines[i].instrument=0;
          else lasti=t.lines[i].instrument;
        }
        t.lines[i].note=(t.lines[i].note << 2);
      }
    }
    int maxINum=0;
    int maxILen=0;
    for (int[] line : il) {
      maxINum=max(maxINum, line[0]+1);
      maxILen=max(maxILen, line[1]+1);
    }
    int overflowIlIndex=max(0,maxINum-32);
    int overflowIlLength=max(0,maxILen-64);
    song.instruments=new Instrument[maxINum];
    int[] iLengths=new int[maxINum];
    for (int[] line : il)
      // Find used length of instrument (+1 corrects for first index zero)
      iLengths[line[0]]=max(iLengths[line[0]], line[1]+1);
    for (int i=1; i<maxINum; i++) {
      // Make room for end jump
      iLengths[i]++;
      println_debug("Make instrument "+i+" length "+(iLengths[i]));
      song.instruments[i]=new Instrument(iLengths[i]);
      // End jump, jumps to instrument 0
      song.instruments[i].lines[iLengths[i]-1].command=0;
      song.instruments[i].lines[iLengths[i]-1].param=0;
    }
    boolean terminalSeven=false;
    for (int[] line : il) {
      int command=(line[2]>>4)&0xF;
      int param=line[2]&0xF;
      song.instruments[line[0]].lines[line[1]].command=command;
      song.instruments[line[0]].lines[line[1]].param=param;
      if(command==7)terminalSeven=true;
    }
    if(terminalSeven)println_warn("Song contains illegal command 7 at least once!");
    // Force instrument 0 to be suitable end location for other instruments
    song.instruments[0]=new Instrument(2);
    // Command 4F = pause 15 frames
    song.instruments[0].lines[0].command=0x4;
    song.instruments[0].lines[0].param=0xF;
    // Command 00 = jump to instrument 0 (self)
    song.instruments[0].lines[1].command=0x0;
    song.instruments[0].lines[1].param=0x0;
    // Compress everything before checking limits
    song.contiguateTracks();
    println_info("Loaded song. Result:");
    println_info(" "+song.length()+" used song lines");
    println_info(" "+song.tracks.length+" used tracks ("+trackSize+" rows each)");
    println_info(" "+song.instruments.length+" instruments");
    if (overflowSl>0 || overflowTl>0 || overflowIlIndex>0 || overflowIlLength>0) {
      println_warn("The song would play incorrectly or crash the packer script if used in the real Phasor environment! Reasons:");
      if (overflowSl>0)println_warn(" Song size limit (256 lines) exceeded by "+overflowSl+" line"+(overflowSl==1?"":'s'));
      if (overflowTl>0)println_warn(" Track count limit (256 tracks) exceeded by "+overflowTl+" track"+(overflowTl==1?"":'s'));
      if (overflowIlIndex>0)println_warn(" Instrument count limit (32 instruments) exceeded by "+overflowIlIndex+" instrument"+(overflowIlIndex==1?"":'s'));
      if (overflowIlLength>0)println_warn(" Instrument length limit (64 lines) exceeded by "+overflowIlLength+" line"+(overflowIlLength==1?"":'s')+" in one or more instruments");
    }
    seek(0,0);
  }
  public void seek(int songLine,int trackLine){
    boolean wasPlaying=playing;
    playing=false;
    initSilence(); // clear current sounds
    // Calculate which frame we should be on at this part of the song.
    // Also tick from the start to this point if we're in accurate mode.
    currentFrame=-1; // Compensate for updating to desired position on the NEXT frame
    trackTimer=0; // increment track line immediately
    // Run from the start
    currentTrackLine=trackSize-1;
    currentSongLine=-1;
    for(int i=0;i<=songLine;i++){
      // Do all lines in the track unless we're on the destination track
      int ts=(i==songLine)?trackLine:trackSize;
      for(int j=0;j<ts;j++){
        currentFrame+=songSpeed;
        for(int k=0;k<songSpeed;k++)tick();
      }
    }
    currentTrackLine=(trackLine+trackSize-1)%trackSize; // when incremented (see above), go to desired track line
    currentSongLine=songLine-1;
    playing=wasPlaying; // Restore playing state
  }
  public void initSilence(){
    // Silence output
    output=0;
    amplitudeNow=0;
    // Reset registers
    c_inst=new int[] {0,0,0};
    c_instLine=new int[] {0,0,0};
    c_pw=new int[] {0,0,0};
    c_ivolume=new int[] {0,0,0};
    c_noise=new int[] {0,0,0};
    c_instDelay=new int[] {0,0,0};
    c_vibDepth=new int[] {0,0,0};
    c_vibRate=new int[] {0,0,0};
    c_noteWhole=new int[] {0,0,0};
    c_noteFract=new int[] {0,0,0};
    c_glide=new int[] {0,0,0};
    c_fade=new int[] {0,0,0};
    c_pwDelta=new int[] {0,0,0};
    c_vibPos=new int[] {0,0,0};
    c_transp=new int[] {0,0,0};
    c_track=new int[] {0,0,0};
    c_lasti=new int[] {0,0,0};
    c_freq=new int[] {0,0,0};
    c_phase=new int[] {0,0,0};
    c_phase_hq=new int[] {0,0,0};
    c_volume=new int[] {0,0,0};
    filtStage1=0;
    filtStage2=0;
    filtStage1High=0;
    filtStage2High=0;
    noiseVol=0;
    noiseReg=0x0033;
    //Wipe AFBs
    afbArray.clear();
  }
}
class Song {
  SongLine[] lines;
  Track[] tracks;
  Instrument[] instruments;
  Song(int len) {
    lines=new SongLine[len];
    for(int i=0;i<len;i++)lines[i]=new SongLine();
  }
  int length(){
    return lines.length;
  }
  int illegalReasonFlags(){
    // Bitmask:
    // 1=Song too long
    // 2=Too many tracks
    // 4=Too many instruments
    // 8=Instrument too long
    int r=0;
    if(lines.length>256)r|=1; // MAXSLEN=256
    if(tracks.length>96)r|=2; // SNG_TRACK(n>=96) = SNG_TRANSP
    if(instruments.length>32)r|=4; // MAXINSTR 32
    for(int i=0;i<instruments.length;i++)
      if(instruments[i].length()>64)r|=4; // MAXILEN=64
    return r;
  }
  String[] illegalReasonStrings(){
    ArrayList<String> al=new ArrayList<String>();
    if(lines.length>256)al.add("Song length (lines) exceeds limit 256 (is "+lines.length+')');
    if(tracks.length>96)al.add("Used tracks exceeds limit 96 (is "+tracks.length+')');
    if(instruments.length>32)al.add("Defined instruments exceeds limit 32 ( is"+instruments.length+')');
    String instTooLong=null;
    for(int i=0;i<instruments.length;i++){
      if(instruments[i].length()>64){
        if(instTooLong==null)instTooLong="Instrument length exceeds limit 64:";
        instTooLong+="\n Instrument "+i+" length is "+instruments[i].length();
      }
    }
    return (String[])al.toArray();
  }
  void contiguateTracks(){
    // Move tracks close together to make better use of space limits
    // Does NOT produce the same data order as Phasor's actual packing algorithm!
    println_debug("Making tracks contiguous:");
    boolean[] trackUsed=new boolean[tracks.length];
    for(int i=0;i<lines.length;i++){
      trackUsed[lines[i].order[0]]=true;
      trackUsed[lines[i].order[1]]=true;
      trackUsed[lines[i].order[2]]=true;
    }
    int usedTracks=0;
    for(int i=0;i<tracks.length;i++){
      if(trackUsed[i])usedTracks++;
    }
    int[] newOrder=new int[tracks.length];
    Track[] newTracks=new Track[usedTracks];
    int newIndex=0;
    for(int i=0;i<tracks.length;i++){
      if(trackUsed[i]){
        newTracks[newIndex]=tracks[i];
        newOrder[i]=newIndex;
        newIndex++;
      }
    }
    tracks=newTracks;
    for(int i=0;i<lines.length;i++){
      // Replace track references in song
      lines[i].order[0]=newOrder[lines[i].order[0]];
      lines[i].order[1]=newOrder[lines[i].order[1]];
      lines[i].order[2]=newOrder[lines[i].order[2]];
    }
    println_debug(" Done!");
  }
}
class SongLine {
  int[] order;
  int[] transp;
  SongLine(){
    order=new int[]{0,0,0};
    transp=new int[]{0,0,0};
  }
}
class Track {
  TrackLine[] lines;
  Track(int len) {
    lines=new TrackLine[len];
    for (int i=0; i<len; i++)lines[i]=new TrackLine();
  }
  int length(){
    return lines.length;
  }
}
class TrackLine {
  int note;
  int instrument;
  TrackLine(){
    note=0;
    instrument=0;
  }
}
class Instrument {
  InstrumentLine[] lines;
  Instrument(int len){
    lines=new InstrumentLine[len];
    for (int i=0; i<len; i++)lines[i]=new InstrumentLine();
  }
  int length(){
    return lines.length;
  }
}
class InstrumentLine{
  int command;
  int param;
  InstrumentLine(){
    command=0;
    param=0;
  }
}
class OutputFilter {
  float dt=0;
  float dcRC=0;
  float dcA=0;
  float dcYLast=0;
  float dcXLast=0;
  float lpRC=0;
  float lpA=0;
  float lpYLast=0;
  float lpFactor=0;
  float amplitude=0;
  void setDt(float dt) {
    this.dt=dt;
    if (dcRC <=0 || dt <= 0)dcA=0;
    else dcA=dcRC/(dcRC+dt);
    if (lpRC <=0 || dt <= 0)lpA=0;
    else lpA=dt/(lpRC+dt);
  }
  void setDcRC(float RC) {
    this.dcRC=RC;
    if (dcRC <= 0 || dt <= 0)dcA=0;
    else dcA=dcRC/(dcRC+dt);
  }
  void setLpRC(float RC) {
    this.lpRC=RC;
    if (lpRC <=0 || dt <= 0)lpA=0;
    else lpA=dt/(lpRC+dt);
  }
  void setLpFactor(float lpFactor) {
    this.lpFactor=min(max(0,lpFactor),1);
  }
  void setAmplitude(float amplitude) {
    this.amplitude=min(max(0,amplitude),1);
  }
  private float sampleDc(float x) {
    float y = dcA*(dcYLast+x-dcXLast);
    dcXLast=x;
    dcYLast=y;
    return y;
  }
  float doSample(float x) {
    float xd = sampleDc(x);
    float y = (lpA * xd) + ((1-lpA) * lpYLast);
    lpYLast=y;
   return (xd+(y*lpFactor))*amplitude;
  }
}
class AudioFrameBuffer {
  int frameIndex;
  int songLine;
  int trackLine;
  byte[] samples=new byte[312];
  int maxAmplitude;
}
