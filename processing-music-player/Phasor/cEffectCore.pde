/*public class EC_State{
  int[] r=new int[32];
  int[] io=new int[64];
  int[] ram=new int[0xFFFF];
  boolean c,z,n,v,s,h,t,i;
  int sp;
}
static int sreg_c=0,sreg_z=1,sreg_n=2,sreg_v=3,sreg_s=4,sreg_h=5,sreg_t=6,sreg_i=7;
public abstract class EC_Operation{
  public abstract int run(EC_State state); // Run and return cycles taken
  public boolean bit(int v,int b){return ((v>>b)&1)==1;}
  public boolean nbit(int v,int b){return !bit(v,b);}
}
public class OP_ADC extends EC_Operation{
  int Rd,Rr;
  public OP_ADC(int Rd,int Rr){this.Rd=Rd&0x31;this.Rr=Rr&0x31;}
  public int run(EC_State s){
    int R=(s.r[Rd]+s.r[Rr]+(s.c?1:0));
    byte Rb=(byte)R;
    byte Rh=(byte)((Rd&0xF0)|(R&0x0F));
    s.c=(Rb!=R); s.z=(Rb==0x00); s.n=(Rb<0);
    s.v=(bit(s.r[Rr],7)==bit(s.r[Rd],7))&&(bit(s.r[Rr],7)!=bit(s.r[R],7));
    s.s=s.n^s.v; s.h=(Rb!=Rh);
    s.r[Rd]=R&0xFF;
    return 1;
  }
}
public class OP_ADD extends EC_Operation{
  int Rd,Rr;
  public OP_ADD(int Rd,int Rr){this.Rd=Rd&0x31;this.Rr=Rr&0x31;}
  public int run(EC_State s){
    int R=(s.r[Rd]+s.r[Rr])&0xFF;
    s.c=(bit(s.r[Rd],7)&&bit(s.r[Rr],7))||(bit(s.r[Rr],7)&&nbit(R,7))||(nbit(R,7)&&bit(s.r[Rd],7));
    s.z=(R==0x00);
    s.n=bit(R,7);
    s.v=(bit(s.r[Rd],7)&&bit(s.r[Rr],7)&&nbit(R,7))||(nbit(s.r[Rd],7)&&nbit(s.r[Rr],7)&&bit(R,7));
    s.s=s.n^s.v;
    s.c=(bit(s.r[Rd],3)&&bit(s.r[Rr],3))||(bit(s.r[Rr],3)&&nbit(R,3))||(nbit(R,3)&&bit(s.r[Rd],7));
    s.r[Rd]=R;
    return 1;
  }
}*/
