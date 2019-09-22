public class CustomEffects extends EffectHandlerGroup {
  public CustomEffects(){
    effects.add(new SimpleEffects());
  }
}
class SimpleEffects extends EffectHandler {
  int dotCycle;
  public void cycle(String effect,Copper copper,int cycle){
    switch(effect){
      case "l_thinsine":
        if(cycle==0){
          int sine=byte(255-copper.mathTables.sin8(copper.getFrameIndex()+(copper.getRasterLine()*3)));
          dotCycle = 393+128+sine;
        }
        if(cycle==dotCycle)copper.setColor(0x7777);
        if(cycle==dotCycle+5)copper.setColor(0x3333);
        break;
    }
  }
  public void setupHandler(Copper copper){
    copper.loadColor(0x3333);
    copper.loadColor(0x7777);
    copper.registerEffect(this,"l_thinsine");
  }
}

String[] data_testeffect = {
  "#include \"demo.i\"",
  "    .global  l_vu",
  "l_vu:",
  "    DE203",
  "    in  r20, PORTC",
  "    subi  r20, 32",
  "    brpl  1f",
  "    neg  r20",
  "1:",
  "    lsl  r20",
  "    lsl  r20",
  "    ldi  r21, 127",
  "    sub  r21, r20",
  "    lsl  r21",
  "    ldi  r22, 0x54",
  "    sbrc  r19, 0",
  "    ldi  r22, 0x45",
  "    ldi  r23, 0xaa",
  "    mov  r16, r21",
  "    rcall  delayxplus16",
  "    out  PORTD, r22",
  "    mov  r16, r20",
  "    rcall  delayxplus16",
  "    out  PORTD, r23",
  "    mov  r16, r20",
  "    rcall  delayxplus16",
  "    mov  r16, r20",
  "    rcall  delayxplus16",
  "    out  PORTD, r22",
  "    mov  r16, r20",
  "    rcall  delayxplus16",
  "    out  PORTD, r2",
  "    mov  r16, r21",
  "    rcall  delayxplus16",
  "    DE78",
  "    rjmp  endofline"
};