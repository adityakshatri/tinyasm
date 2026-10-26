
; Load 42 into t0
dw moviwq0
dw 42

; Load 8 into t1
dw moviwq1
dw 8

; Add t1 to t0: t0 = 42 + 8 = 50
dw addwq0q1

; Stop the VM
dw halt
