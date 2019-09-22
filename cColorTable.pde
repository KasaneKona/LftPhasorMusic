public class ColorTable{
  int mapType;
  private byte[] colorBytes = new byte[0x30000]; // 0x10000 * 3
  private int[] initFlags = new int[0x800]; // 0x10000 / 32
  private float[] dacTable = {-0.026,0.048,0.131,0.214,0.297,0.330,0.462,0.546,0.630,0.710,0.794,0.878,0.962,1.046,1.125,1.209};
  float fullScale = (dacTable[3])*7f/3f; // Coefficient of 7/3 as full saturation is 7 and color burst amplitude is 3 
  public ColorTable(int type){
    this.mapType=type;
  }
  private boolean hasColor(int c){
    c&=0xFFFF;
    // Bitwise magic
    return (initFlags[c>>5]&(1<<(c&31)))>0;
  }
  public color get(int c){
    c&=0xFFFF;
    // Only generate the color if we really need to
    if(!hasColor(c)){
      initColor(c);
    }
    int offset=c+c+c;
    return color(colorBytes[offset+0]&0xFF,colorBytes[offset+1]&0xFF,colorBytes[offset+2]&0xFF);
  }
  public void initColor(int c){
    println_debug(String.format("Init color 0x%04X",c));
    int even=(c>>8)&0xFF;
    int odd=c&0xFF;
    int evenFirst=even&0xF;
    int evenSecond=(even>>4)&0xF;
    int oddFirst=odd&0xF;
    int oddSecond=(odd>>4)&0xF;
    float evenFirstLevel=getLevel(evenFirst);
    float evenSecondLevel=getLevel(evenSecond);
    float oddFirstLevel=getLevel(oddFirst);
    float oddSecondLevel=getLevel(oddSecond);
    // Let's get our average luminance (Y) in range 0..1
    float yOdd=(oddFirstLevel+oddSecondLevel)*0.5f;
    float yEven=(evenFirstLevel+evenSecondLevel)*0.5f;
    float y=(yOdd+yEven)*0.5f;
    // Now let's perform the sum/difference formula to get U and V. We can do this with just the first value of each line.
    float u=((oddFirstLevel-yOdd)+(evenFirstLevel-yEven))*0.58333333; // Coefficient of 7/12 for unknown reason
    float v=((oddFirstLevel-yOdd)-(evenFirstLevel-yEven))*0.58333333;
    float r,g,b;
    if(mapType>0){
      // Use YUV color space
      // For map 2, U is doubled to match Barta Zoli's recording
      if(mapType>1)u*=2;
      r=y+(1.140*v);
      g=y+(-0.395*u)+(-0.581*v);
      b=y+(2.032*u);
    }else{
      // Roughly match colors seen on Linus' TFT monitor 
      // Use YPbPr colorspace
      r=y+(1.402*v);
      g=y+(-0.344*u)+(-0.714*v);
      b=y+(1.772*u);
    }
    r=min(max(0,r),1);
    g=min(max(0,g),1);
    b=min(max(0,b),1);
    // Gamma correction of 2.8/2.2
    r=pow(r,1.27272727);
    g=pow(g,1.27272727);
    b=pow(b,1.27272727);
    int offset=c+c+c;
    colorBytes[offset+0]=byte(round(r*255));
    colorBytes[offset+1]=byte(round(g*255));
    colorBytes[offset+2]=byte(round(b*255));
    // Bitwise magic
    initFlags[c>>5]|=(1<<(c&31));
  }
  private float getLevel(int dac){
    float level = dacTable[dac&0xF]-dacTable[3];
    return level/fullScale;
  }
}
