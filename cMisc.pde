public class TimeManager{
  private int startupDelay;
  private float videoFrame;
  int videoFrameTarget;
  private Music musicInstance;
  private NativeSoundPlayer nspInstance;
  private boolean ended;
  private boolean shouldExit;
  private int exitWait;
  private boolean canExit;
  private AudioFrameBuffer lastAfb=new AudioFrameBuffer();
  private boolean recordOutput;
  private boolean init;
  private int syncFrames;
  private int framesPerBuffer;
  private boolean exitOnDone;
  public TimeManager(int audRate,Music mus,int startupDelay,
    boolean recordOutput,boolean exitOnDone
  ){
    this.recordOutput=recordOutput;
    this.musicInstance=mus;
    this.startupDelay=abs(startupDelay);
    this.framesPerBuffer=10;
    this.syncFrames=25;
    this.exitOnDone=exitOnDone;
    nspInstance=new NativeSoundPlayer(musicInstance,audRate,recordOutput?new File(sketchPath(mus.isHighQuality()?"soundtrack_hq.wav":"soundtrack.wav")):null);
    if(startupDelay<=0){
      beginSong();
      startupDelay=0;
    }
    init=true;
  }
  private void beginSong(){
    nspInstance.open();
    musicInstance.setPlaying(true);
  }
  public void tick(float fps){
    if(!init)return;
    if(!shouldExit){
      canExit=false;
    }else{
      canExit=exitWait<0; // Wait 5 additional frames to ensure file is saved
      if(exitWait<0 && recordOutput){
        recordOutput=false;
        //fileOut.endRecord();
        //fileOut.save();
      }
      exitWait--;
    }
    if(startupDelay>0){
      startupDelay--;
      // Skip tick if hasn't reached 0 yet.
      if(startupDelay>0)return;
      beginSong();
    }else{
      // Increment frame by correct amount if needed
      // Allow just over 1 buffer length of hysteresis
      if(videoFrame<videoFrameTarget+(framesPerBuffer+1))videoFrame+=50f/fps;
      // Fix backwards seeking
      boolean backSeek=false;
      if(videoFrame>videoFrameTarget){
        backSeek=true;
        videoFrame=videoFrameTarget;
      }
      // Synchronize with audio
      videoFrameTarget=max(music.getCurrentFrame()-syncFrames,0);
      videoFrame=max(videoFrame,videoFrameTarget-(framesPerBuffer+1));
      // Prevent negative frames
      if(lastAfb.frameIndex<=round(videoFrame) || backSeek){
        AudioFrameBuffer nextAfb=musicInstance.getNextAfb(getVideoFrame());
        if(nextAfb!=null)lastAfb=nextAfb;
      }
    }
    if(checkPlaybackFinished() && !ended){
      end("playback finished",50);
    }
  }
  public int getVideoFrame(){
    return round(videoFrame);
  }
  public AudioFrameBuffer getLastAfb(){
    return lastAfb;
  }
  public void end(String message,int waitFrames){
    if(ended)return;
    if(message.length()>0)println_info("Ended demo ("+message+")");
    ended=true;
    exitWait=waitFrames;
    shouldExit=exitOnDone;
    nspInstance.close();
  }
  public boolean canExit(){
    return canExit;
  }
}
public class MathTables{
  private int[] sinTbl=new int[256];
  private int[] freqTbl=new int[14];
  int sin8(int angle){
    return sinTbl[angle&0xFF];
  }
  int freq(int note){
    return freqTbl[note];
  }
  public MathTables(){
    for(int i=0;i<256;i++){
      int value = round(127 * sin(i * TWO_PI / 256));
      sinTbl[i]=(value+255)&255;
    }
    freqTbl[0]=0;
    for(int i=0;i<13;i++){
      double freq = 440 * pow(pow(2, 1.0/12), i + 5 * 12 - 9 - 24);
      int rounded = (int)(freq * 65536 / 15625);
      freqTbl[i+1]=rounded;
    }
  }
}
