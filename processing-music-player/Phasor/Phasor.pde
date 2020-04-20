import javax.sound.sampled.*;
import java.util.Arrays;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.nio.FloatBuffer;
import java.nio.ByteBuffer;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;

// Color map type:
// 0: YPbPr + Gamma (Match some of LFT's camera recording, not recommended)
// 1: YUV (Correct, recommended)
// 2: Y(2U)V (Match Barta Zoli's video capture)
int colorMapType=1;
// Sample rate of audio
int audioSampleRate=48000;
// Enable modified sound engine for higher quality audio
boolean highQualityAudio=false;
// Simulate implicit filtering in LFT's recording setup
boolean simulateImplicitFilter=true;
// How long to wait before starting the demo
int startupDelayFrames=10;
// Border:
// 0: Borderless
// 1: Border visible
// 2: Debug (show raw raster with mask bars and render boxes) 
int border=1;
// Output audio to file (no video recording yet!)
boolean recordOutput=false;
boolean[] initialMutes = {false, false, false, false};
// Message/warning configs
int closeOnWarningLimit=1;
int messageLevel=MessageLevel.DEBUG;
// What to set the window title to
String windowTitle="Phasor Demo by LFT - Player by KasaneKona";
// ~~~~~~~~~~~~~~~~ Everything below here is internal state, don't touch it!
int warnings;
Music music;
TimeManager timeManager;
MathTables mathTables;
Copper copper;
Story story;

void settings(){
  noSmooth();
  size(256,256); // Dummy size, set conditional size in setup
}

void setup(){
  surface.setTitle("Loading...");
  background(0);
  if(border>=2)sizeCentered(1135,312);
  if(border==1)sizeCentered(714,542); // 893 * 0.8
  if(border<=0)sizeCentered(612,512); // 764 * 0.8
  mathTables=new MathTables();
  music=new Music(data_song,24,4,mathTables);
  music.setHighQuality(highQualityAudio);
  music.setFiltered(simulateImplicitFilter);
  for(int i = 0; i < 4; i++) {
    if(!initialMutes[i]) continue;
    music.setChannelMuted(i, true);
    println_info("Channel "+i+" initially muted!");
  }
  timeManager=new TimeManager(audioSampleRate,music,startupDelayFrames,recordOutput,true);
  copper = new Copper(mathTables);
  story = new Story(data_story,24,4);
  copper.useStory(story);
  frameRate(60); // Better native output. Time manager will process at 50Hz automatically.
  textSize(15);
  textLeading(15);
  surface.setTitle(windowTitle);
}
void sizeCentered(int w,int h){
  surface.setLocation((displayWidth-w)/2,(displayHeight-h)/2);
  surface.setSize(w,h);
  background(0);
}
void draw(){
  timeManager.tick(frameRate);
  copper.frame(timeManager.getVideoFrame(),timeManager.getLastAfb(),border>=2);
  background(0); // Show black if anything ever doesn't render
  if(border<=0)image(copper.output().get(274,38,764,256),0,0,width,height);
  else if(border==1)image(copper.output().get(213,30,892,271),0,0,width,height);
  else {
    image(copper.output(),0,0,width,height);
    noFill();
    float pulse=sin(millis()/318f);
    pulse*=pulse*64;
    stroke(#FF0000,pulse);
    rect(213,30,892-1,271-1);
    rect(274,38,764-1,256-1);
  }
  if(messageLevel>=MessageLevel.DEBUG){
    String debugWindow=
    "FPS: "+round(frameRate)+'\n'+
    "FRAME AUD: "+music.getCurrentFrame()+'\n'+
    "FRAME TGT: "+timeManager.videoFrameTarget+'\n'+
    "FRAME VID: "+timeManager.getVideoFrame()+'\n'+
    "FRAME SYNC: "+timeManager.getLastAfb().frameIndex+'\n'+
    "TL SYNC: "+timeManager.getLastAfb().trackLine+'\n'+
    "SL SYNC: "+timeManager.getLastAfb().songLine+'\n'+
    "FIN SONG: "+music.songFinished+'\n'+
    "FIN STORY: "+story.finished;
    int numLines=debugWindow.split("\n").length;
    noStroke();
    fill(32,128);
    rect(0,0,textWidth(debugWindow)+4,(numLines*15)+4);
    rect(0,height-128,312,128);
    fill(255);
    text(debugWindow,2,15);
    noFill();
    stroke(255);
    beginShape();
    for(int i=0;i<312;i++){
      int y=min(max(-128,round(-timeManager.getLastAfb().samples[i]>>1)),127)+height-64;
      vertex(i,y);
    }
    endShape();
  }
  if(timeManager.canExit())super.exit();
}
void exit(){
  timeManager.end("program exit",0);
}
void keyPressed(){
  if(key >= '1' && key <= '4'){
    boolean wasMuted=music.isChannelMuted(key-'1');
    music.setChannelMuted(key-'1',!wasMuted);
    println_info("Channel "+(key-'1')+(wasMuted?" unmuted!":" muted!"));
  }else if(key == 's' || key == 'S'){
    println_info("Seek test!");
    music.seek(24,0);
  }else if(key == 'h' || key == 'H'){
    boolean newHq=!music.isHighQuality();
    music.setHighQuality(newHq);
    println_info("Set high-quality to "+newHq);
  }
}
public static class MessageLevel{
  static int WARN=0;
  static int INFO=1;
  static int DEBUG=2;
}
// These can redirect to a logger or whatever you want!
void println_any(String message){
  println(message);
}
void println_error(String message){
  println("[ERROR] "+message);
  timeManager.end("an error occurred",1);
}
void println_warn(String message){
  println("[WARN]  "+message); // Extra space for alignment
  warnings++;
  if(warnings>=closeOnWarningLimit)timeManager.end("warnings exceeded limit",1);
}
void println_info(String message){
  if(messageLevel>=MessageLevel.INFO)println("[INFO]  "+message); // Extra space for alignment
}
void println_debug(String message){
  if(messageLevel>=MessageLevel.DEBUG)println("[DEBUG] "+message);
}
boolean checkPlaybackFinished(){
  return music.songFinished && story.finished;
}
