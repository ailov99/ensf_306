using BitSAD
using Ghost

using TimerOutputs 
tmr2 = TimerOutput()
Ghost.set_tmr(tmr2)
BitSAD.set_tmr(tmr2)

f(x, y) = x * y
x, y = SBitstream(0.3), SBitstream(0.5)

f_verilog, f_circuit = generatehw(f, x, y)
# print(f_verilog)