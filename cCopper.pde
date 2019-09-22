public class Copper { // Scanline renderer (name is used in Phasor code, originated from Amiga co-processor)
  private int scanLine;
  private int rasterLine;
  private int segmentLine;
  private int frameIndex;
  private color currentColor;
  private AudioFrameBuffer audio;
  private PGraphics scanBuffer;
  private ColorTable colTable;
  private MathTables mathTables;
  private HashMap<String,EffectHandler> registeredEffectHandlers;
  private ArrayList<EffectHandler> effectHandlerUpdateList;
  private Story story;
  private boolean hasError;
  private String lastSegmentName;
  public Copper(MathTables mathTables){
    scanBuffer=createGraphics(1135,312);
    scanBuffer.beginDraw();
    scanBuffer.textSize(15);
    scanBuffer.textLeading(0);
    scanBuffer.endDraw();
    this.mathTables=mathTables;
    
    colTable=new ColorTable(colorMapType);
    registeredEffectHandlers=new HashMap<String,EffectHandler>();
    effectHandlerUpdateList=new ArrayList<EffectHandler>();
    (new BuiltInEffects()).setupHandler(this);
    (new CustomEffects()).setupHandlers(this);
  }
  public void useStory(Story story){
    this.story=story;
  }
  public int getScanLine(){return scanLine;}
  public int getRasterLine(){return rasterLine;}
  public int getSegmentLine(){return segmentLine;}
  public int getFrameIndex(){return frameIndex;}
  public void registerEffect(EffectHandler handler,String name){
    if(handler==null)println_error("Effect '"+name+"' has bad handler!");
    else {
      if(registeredEffectHandlers.containsKey(name))println_warn("Overridden handler for effect '"+name+"'!");
      else println_info("Loaded effect '"+name+"'");
      registeredEffectHandlers.put(name,handler);
      if(!effectHandlerUpdateList.contains(handler))effectHandlerUpdateList.add(handler);
    }
  }
  private EffectHandler getEffectHandler(String name){
    // hasKey would not be the same as checking if the object is null!
    if(registeredEffectHandlers.get(name) == null)println_error("Can't find handler for effect '"+name+"'!");
    return registeredEffectHandlers.get(name);
  }
  public boolean hasEffect(String name){
    return registeredEffectHandlers.get(name) != null;
  }
  public void frame(int fInd,AudioFrameBuffer aud,boolean debug){
    if(hasError)return;
    frameIndex=fInd;
    boolean loadedNew=story.setFrame(frameIndex);
    for(EffectHandler eh : effectHandlerUpdateList){
      if(loadedNew){
        eh.loadCopper(this);
      }
      eh.frame(this);
    }
    StoryFrame sf=story.getStoryFrame();
    //doImmediateUnpacks(sf);
    //doImmediateCalls(sf);
    audio=aud;
    scanBuffer.beginDraw();
    scanBuffer.loadPixels();
    lastSegmentName="";
    for(int i=0;i<312;i++){
      if(i>=38 && i<256+38){
        
      }
      scanLine=i;
      drawLine(debug);
      if(hasError)break;
    }
    scanBuffer.updatePixels();
    scanBuffer.endDraw();
  }
  public final void setColor(int c){
    currentColor=colTable.get(c);
  }
  public final void loadColor(int c){
    colTable.get(c);
  }
  private void drawLine(boolean debug){
    if(scanLine>=312)return;
    if(scanLine<8){
      if(debug)currentColor=colTable.get(0x6455); // Mark vertical sync
      else currentColor=colTable.get(0x3333); // Fill with black
      for(int cycle=0;cycle<1135;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
    }else if(scanLine<22 || scanLine>=309){
      if(debug)currentColor=colTable.get(0x3246); // Mark hidden lines
      else currentColor=colTable.get(0x3333); // Fill with black
      for(int cycle=0;cycle<1135;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
    }else{
      //Fill with black
      currentColor=colTable.get(0x3333);
      for(int cycle=0;cycle<1135;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
      boolean flagNew=false;
      if(scanLine>=38 && scanLine<256+38){
        rasterLine=scanLine-38;
        String currentSegmentName="l_thinsine";
        if(!currentSegmentName.equals(lastSegmentName)){
          lastSegmentName=currentSegmentName;
          if(debug)flagNew=true;
        }
        segmentLine=256-rasterLine;
        if(flagNew)for(int cycle=131;cycle<224;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=colTable.get(0xAAAA);
        if(hasEffect(currentSegmentName) || !debug){
          EffectHandler currentSegmentHandler=getEffectHandler(currentSegmentName);
          if(currentSegmentHandler==null){
            hasError=true;
            return; // getEffectHandler already handled the error so we'll silently quit rendering
          } else for(int cycle=(flagNew?224:131);cycle<1121;cycle++){
            currentSegmentHandler.cycle(currentSegmentName,this,cycle-131);
            scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
          }
        }
      }
      if(debug){
        //Mark horizontal sync
        currentColor=colTable.get(0x0660);
        for(int cycle=0;cycle<71;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
        //Mark back porch
        currentColor=colTable.get(0x6033);
        for(int cycle=71;cycle<213;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
        //Mark front porch
        currentColor=colTable.get(0x3434);
        for(int cycle=1106;cycle<1135;cycle++)scanBuffer.pixels[scanLine*1135+cycle]=currentColor;
      }
    }
  }
  public PImage output(){
    return scanBuffer.get();
  }
}
public abstract class EffectHandler {
  // Runs only once when loading. Must register capable effects to the Copper.
  // Returns this.
  public abstract void setupHandler(Copper copper);
  // Renders any effects this handler is capable of.
  // Undefined or no action for incapable effect.
  // Cycles range from 0 to 1134 inclusive, visible window is 213 to 1105 inclusive.
  // Get raster line etc. from given Copper object.
  public abstract void cycle(String effect,Copper copper,int cycle);
  // Not required. Runs once when the copperlist updates.
  public void loadCopper(Copper copper){};
  // Not required. Runs once at the start of every frame (vsync)
  public void frame(Copper copper){};
  // Using these two methods in non-builtin effects can't be backported to real demo.
}
public abstract class EffectHandlerGroup {
  // In your constructor add new instances of each of your handlers, eg.
  // public MyEffectGroup(){
  //   effects.add(new MySimpleHandler());
  //   effects.add(new MyComplexHandler());
  // }
  public ArrayList<EffectHandler> effects=new ArrayList<EffectHandler>();
  public final void setupHandlers(Copper copper){
    for(EffectHandler eh : effects){
      eh.setupHandler(copper);
    }
  }
}
public class BuiltInEffects extends EffectHandler {
  int cl_flash;
  public void loadCopper(Copper copper){
    cl_flash=8;
  }
  public void frame(Copper copper){
    cl_flash--;
    if(cl_flash<0)cl_flash=0;
  }
  public void cycle(String effect,Copper copper,int cycle){
    switch(effect){
      case "l_white":
        if(cycle==143)copper.setColor(0xAAAA);
        if(cycle==907)copper.setColor(0x3333);
        break;
      case "l_black":
        // Doesn't set anything, assumes frame is already black
        break;
      case "l_flash":
        if(cycle==143)copper.setColor(0x1111*(3+min(cl_flash,7)));
        if(cycle==907)copper.setColor(0x3333);
        break;
    }
  }
  public void setupHandler(Copper copper){
    //copper.loadColor(0x3333);
    //copper.loadColor(0xAAAA);
    for(int i=0;i<=7;i++)copper.loadColor(0x1111*(3+i));
    copper.registerEffect(this,"l_white");
    copper.registerEffect(this,"l_black");
    copper.registerEffect(this,"l_flash");
  }
}
