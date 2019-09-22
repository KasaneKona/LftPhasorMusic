class Story {
  int division;
  int trackSize;
  ArrayList<StoryFrame> fArray;
  int currentSfNumber;
  StoryFrame currentSf;
  boolean finished;
  boolean changed;
  public Story(String[] storyStringArray,int trackSize,int division){
    this.trackSize=trackSize;
    this.division=division;
    loadStory(storyStringArray);
  }
  public boolean setFrame(int frame){
    // Return value is whether to update story position
    if(finished)return false;
    int sfIndex=frame/division;
    boolean advanced=false;
    while(sfIndex>=fArray.get(currentSfNumber+1).startAtFrame){
      if(!advanced)println_debug("Story advanced at tick "+sfIndex);
      advanced=true;
      currentSfNumber++;
      if(currentSfNumber>=fArray.size()-1){
        println_debug("Story finished (size was "+fArray.size()+")");
        finished=true;
        return false;
      }
      currentSf=fArray.get(currentSfNumber);
    }
    return advanced;
  }
  public StoryFrame getStoryFrame(){
    return currentSf;
  }
  public void loadStory(String[] lines){
    int currTime=0;
    String failMessage="";
    int failLine=-1;
    fArray=new ArrayList<StoryFrame>();
    StoryFrame sf=new StoryFrame(0);
    boolean inCopper=false;
    boolean inHint=false;
    for(int i=0;i<lines.length;i++){
      // Trim leading/trailing whitespace, replace all gaps with single space
      String line=lines[i].trim().replaceAll("\\s+"," ");
      if(inCopper){
        if(line.equals("}")){
          inCopper=false;
          println_debug("Story("+(i+1)+"): exit copper");
          continue;
        }else if(line.split(" ").length==2){
          try{
            int size;
            size=Integer.parseInt(line.split(" ")[1]);
            if(size<0){
              failMessage = "Negative segment heights not allowed";
              failLine=i;
              break;
            }else if((size&1)==1){
              failMessage = "Odd segment heights not allowed";
              failLine=i;
              break;
            }else {
              String e=line.split(" ")[0];
              //if(copper.hasEffect(e)){
                sf.copperList.add(new CopperSegment(e,0));
                println_debug("Story("+(i+1)+"): add segment "+e+" (hint)");
                continue;
              //}else{
              //  failMessage = "Unknown effect '"+e+"' (case sensitive!)";
              //  failLine=i;
              //  break;
              //}
            }
          }catch(NumberFormatException e){
            failMessage = "Segment height must be numeric";
            failLine=i;
            break;
          }
        }
      }else if(inHint){
        if(line.equals("}")){
          inHint=false;
          println_debug("Story("+(i+1)+"): exit hint");
          continue;
        }else if(!line.contains(" ")){
          //if(copper.hasEffect(line)){
            sf.copperList.add(new CopperSegment(line,0));
            println_debug("Story("+(i+1)+"): add segment "+line+" (hint)");
            continue;
          //}else{
          //  failMessage = "Unknown effect '"+line+"' (case sensitive!)";
          //  failLine=i;
          //  break;
          //}
        }
      }else{
        // Things start getting very ugly here. That's what I get for porting this section from C (sscanf) to Java
        if(line.replaceAll("[0-9a-fA-F]+","").equals(":")){ // Funky way of checking number:number syntax
          int diff = Integer.parseInt(line.split(":")[0],16) * trackSize + Integer.parseInt(line.split(":")[1],16) - currTime;
          if(diff>0){
            currTime+=diff;
            fArray.add(sf);
            sf=new StoryFrame(currTime);
            println_debug("Story("+(i+1)+"): update time to "+line);
            continue;
          }
          failMessage = "Time "+(currTime+diff)+" is not after time "+currTime;
          failLine=i;
          break;
        }else if(line.startsWith("unpack ") && line.split(" ").length==2){
          sf.immediateUnpacks.add(line.split(" ")[1]);
          println_debug("Story("+(i+1)+"): add immediate unpack ("+line.split(" ")[1]+")");
          continue;
        }else if(line.startsWith("call ") && line.split(" ").length==2){
          sf.immediateCalls.add(line.split(" ")[1]);
          println_debug("Story("+(i+1)+"): add immediate call ("+line.split(" ")[1]+")");
          continue;
        }else if(line.equals("copper {")){
          inCopper=true;
          println_debug("Story("+(i+1)+"): enter copper");
          continue;
        }else if(line.equals("hint {")){
          inHint=true;
          println_debug("Story("+(i+1)+"): enter hint");
          continue;
        }else if(line.startsWith("main ") && line.split(" ").length==2){
          sf.mainCall=line.split(" ")[1];
          println_debug("Story("+(i+1)+"): set main call ("+line.split(" ")[1]+")");
          continue;
        }else if(line.startsWith("vblank ") && line.split(" ").length==2){
          sf.vBlankCall=line.split(" ")[1];
          println_debug("Story("+(i+1)+"): set vblank call ("+line.split(" ")[1]+")");
          continue;
        }
      }
      failMessage = "Syntax error in '"+line+"'";
      failLine=i;
      break;
    }
    if(failLine>=0){
      println_error("Error loading story (line "+(failLine+1)+"): "+failMessage);
    }
  }
  public boolean isFinished(){
    return finished;
  }
}
public class CopperSegment {
  String effectName;
  int effectHeight;
  CopperSegment(String e,int h){
    effectName=e;
    effectHeight=h;
  }
}
public class StoryFrame {
  int startAtFrame;
  ArrayList<String> immediateUnpacks;
  ArrayList<String> immediateCalls;
  ArrayList<CopperSegment> copperList;
  String mainCall;
  String vBlankCall;
  StoryFrame(int f){
    startAtFrame=f;
    immediateCalls=new ArrayList<String>();
    copperList=new ArrayList<CopperSegment>();
    mainCall="";
    vBlankCall="";
  }
}
