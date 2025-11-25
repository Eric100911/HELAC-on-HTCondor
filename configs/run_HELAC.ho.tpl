set cmass = 1.54845d0
set bmass = 4.83020d0
set preunw = 36000
set unwevt = 100000
set nmc = 200000
set nopt = 20000
set nopt_step = 20000
set noptlim = 200000
set seed = MY_SEED
set parton_shower = 1
set minptconia = 4.0d0
set minptbonia = 6.0d0
set minyrapconia = -3.0d0
set maxyrapconia = 3.0d0
set minyrapbonia = -3.0d0
set maxyrapbonia = 3.0d0
generate g g > cc~(3S11)  cc~(3S11) bb~(3S18)
launch
exit
