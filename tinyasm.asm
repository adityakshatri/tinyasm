format ELF64 executable 3
entry _start

include 'tinyasm_insn_helpers.asm'
include 'tinyasm_insn_list.asm'
include 'tinyasm_registers.asm'

tiny_insns define_icodes, 0


section '.data' data readable writeable
    file_desc rq 1
    filename db "dump.bin", 0
 

section '.mem' data readable writeable
    QBX_MEM_SIZE = 1024 * 16  ; 16 K
    qbx_mem db QBX_MEM_SIZE dup ?

segment readable writeable

    qbx_mem rb QBX_MEM_SIZE + 1
    filename rb 4096

    msg_usage db "Usage: qbx <bytecode-file>", 10
    msg_usage_len = $ - msg_usage

    msg_open_error db "qbx: cannot open input file", 10
    msg_open_error_len = $ - msg_open_error

    msg_read_error db "qbx: failed to read input file", 10
    msg_read_error_len = $ - msg_read_error

    msg_too_large db "qbx: program exceeds 16 KiB", 10
    msg_too_large_len = $ - msg_too_large

    msg_read_len db "Bytes read: "
    msg_read_len_len = $ - msg_read_len

    ; Buffer for the decimal byte count and newline.
    number_buffer rb 32

    qbx_program_size rq 1

segment readable executable


_start:
    ; argc must be 2: executable + filename.
    mov rax, [rsp]
    cmp rax, 2
    jne usage_error

    ; argv[1] is at rsp + 16.
    mov rsi, [rsp + 16]

    ; openat(AT_FDCWD, filename, O_RDONLY, 0)
    mov eax, 257
    mov rdi, -100
    xor edx, edx
    xor r10d, r10d
    syscall

    test rax, rax
    js open_error

    mov r12, rax

    ; Read up to QBX_MEM_SIZE + 1 bytes.
    ; The extra byte detects oversized programs.
    xor eax, eax
    mov rdi, r12
    lea rsi, [qbx_mem]
    mov edx, QBX_MEM_SIZE + 1
    syscall

    test rax, rax
    js read_error

    ; Reject programs larger than 16 KiB.
    cmp rax, QBX_MEM_SIZE
    ja too_large

    ; Preserve the actual number of bytes read.
    mov [qbx_program_size], rax

    ; Print "Bytes read: "
    mov eax, 1
    mov edi, 1
    lea rsi, [msg_read_len]
    mov edx, msg_read_len_len
    syscall

    ; Convert byte count to decimal.
    mov rax, [qbx_program_size]
    lea rsi, [number_buffer + 31]
    mov byte [rsi], 10
    mov ecx, 1

.convert:
    xor edx, edx
    mov ebx, 10
    div rbx

    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc ecx

    test rax, rax
    jnz .convert

    ; Print digits followed by newline.
    mov eax, 1
    mov edi, 1
    mov edx, ecx
    syscall

    ; Close the input file.
    mov eax, 3
    mov rdi, r12
    syscall


    begin_execution:
        ; prep qbx for execution.
        xor q0, q0
        xor q1, q1
        xor q2, q2
        xor q3, q3
        xor qip, qip
        xor rdi, rdi
        mov qsp, QBX_MEM_SIZE - 1
        if defined(QBX_BUILD_MODE_DEBUG)
            int3         ; breakpoint for the debugger
        end if

    advance:
        move di,word[qbx_mem + qip]
        add qip, 2
     movzx r10, word [qbx_jmp_table + rdi * 2]
        add r10, insn base
        move rax, flags
        sahf
        jmp r10

    ;Temporary endpoint: loading succeeded.
    ; QBX CPU initialization and dispatch go here.
    insn base:

    insn noop:
        nop
    end insn

    insn halt
        ;
        cmp[arg_ptr], 3
        jl quit
        mov r10,[arg_ptr]
        mov rdc, qword [r10+16]
        cmp byte [rdx], 0
        jne quit

    ;dump memory and register to a file
    dump:
        ;Open / Create file (sys_open = 2)
        mov rax, 2          ; syscall: open
        mov rdi, filename   ; file name
        mov rsi, 577        ; O_WRONLY | O_CREAT | O_TRUNC (1 | 64 | 512)
        mov rdx, 0644       ; file permissions
        syscall
        mov [file_desc], rax

        ;Write data to file (sys_write = 1)
        mov rax, 1          ; syscall: write
        mov rdi, [file_desc]; file descriptor
        mov rsi, qbx_mem        ; buffer address
        mov rdx, QBX_MEM_SIZE    ; number of bytes
        syscall

        ;dump registers to file
        mov word [qbx_mem + 0],  q0
        mov word [qbx_mem + 2],  q1
        mov word [qbx_mem + 4],  q2
        mov word [qbx_mem + 6],  q3
        mov word [qbx_mem + 8],  qipw
        mov word [qbx_mem + 10], qspw
        mov word [qbx_mem + 12], qflagsw

        mov rax, 1          ; syscall: write
        mov rdi, [file_desc]; file descriptor
        mov rsi, qbx_mem        ; buffer address
        mov rdx, QBX_MEM_SIZE    ; number of bytes
        syscall
;       Close file (sys_close = 3)
        mov rax, 3          ; syscall: close
        mov rdi, [file_desc]
        syscall

    quit:
        mov eax, 60         ; syscall: exit
        xor edi, edi        ; status: 0
        syscall
    end insn

    //TODO
    ;moves immediate value to register    
    rept TINY_NUM_REGISTERS reg:0 {
        insn moveiwq#reg
            mov r##reg, [word [qbx_mem + qip]]
            add qip, 2
        end insn

        ;byte sized oprands
        insn moveibq#reg
            movzx r##reg, byte [qbx_mem + qip]
            add qip, 1
        end insn
    }

    ;move value between registers
    rept TINY_NUM_REGISTERS tgt:0 {
        rept 4 src:0 {
            if ~(tgt eq \src)
                insn movewq#tgt#src
                    mov r##tgt, r##src
                end insn
                insn movebq#tgt#src
                    movzx r##tgt, byte r##src
                end insn
            end if
        }
    }

    ;store value to direct adress
    rept TINY_NUM_REGISTERS reg:0 {
        insn storewq#reg
            mov rax, [word [qbx_mem + qip]]
            add qip, 2
            mov [qbx_mem + rax], r##reg
        end insn

        insn storebq#reg
            movzx rax, byte [qbx_mem + qip]
            add qip, 1
            mov [qbx_mem + rax], r##regb
        end insn
    }

    ;store value to adress in q0
    rept 3 reg {
        ;word sized
        insn storewq#reg
            move word [qbx_mem + qaddr], q#reg
        end insn

        insn storebq#reg
            move byte [qbx_mem + qaddr], q#regb
        end insn
    }

    rept TINY_NUM_REGISTERS reg:0 {
        insn pushwq#reg
            sub qsp, 2
            mov word [qbx_mem + qsp + 1], q#reg
        end insn

        insn pushbq#reg
            sub qsp, 1
            mov byte [qbx_mem + qsp + 1], q#reg#b
        end insn
    }

    ; pop word-sized value from the stack.
    rept TINY_NUM_REGISTERS reg:0 {
        insn popwq#reg
            mov q#reg, word [qbx_mem + qsp + 1]
            add qsp, 2
        endinsn

        insn popbq#reg
            mov q#reg#b, byte [qbx_mem + qsp + 1]
            add qsp, 1
        endinsn
    }


        ; addition instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn addbq\#dreg\#q#sreg
                       add q\#dreg\#b, q#sreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn addwq\#dreg\#q#sreg
                       add q\#dreg\#w, q#sreg#w
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; subtraction instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn subbq\#dreg\#q#sreg
                       sub q\#dreg\#b, q#sreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn subwq\#dreg\#q#sreg
                       sub q\#dreg\#w, q#sreg#w
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; unsigned multiplication
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn mulbq\#dreg\#q#sreg
                       xor rax, rax
                       mov al, q\#dreg\#b
                       mul q#sreg#b
                       mov q\#dreg\#b, al
                       update_qbx_flags = 1
                  endinsn

                 ; word-sized operands
                 insn mulwq\#dreg\#q#sreg
                      xor rax, rax
                      mov ax, q\#dreg\#w
                      mul q#sreg#w
                      mov q\#dreg\#w, ax
                      update_qbx_flags = 1
                  endinsn
             \}
        }

        ; signed multiplication
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn smulbq\#dreg\#q#sreg
                       xor rax, rax
                       mov al, q\#dreg\#b
                       imul q#sreg#b
                       mov q\#dreg\#b, al
                       update_qbx_flags = 1
                  endinsn

                 ; word-sized operands
                 insn smulwq\#dreg\#q#sreg
                      imul q\#dreg\#w, q#sreg#w
                      update_qbx_flags = 1
                  endinsn
             \}
        }

        ; unsigned division
        rept 3 sreg {
             ; byte-sized operands
             insn divbq#sreg
                  xor dx, dx
                  xor ax, ax
                  mov ax, q0w
                  movzx cx, q#sreg#b
                  div cx
                  mov q0, ax
                  mov q1, dx
                  update_qbx_flags = 1
             endinsn

             ; word-sized operands
             insn divwq#sreg
                  xor rax, rax
                  xor rdx, rdx
                  mov ax, q0w
                  div q#sreg#w
                  mov q0, ax
                  mov q1, dx
                  update_qbx_flags = 1
             endinsn
        }

        ; signed division
        rept 3 sreg {
             ; byte-sized operands
             insn sdivbq#sreg
                  xor dx, dx
                  xor ax, ax
                  mov ax, q0w
                  movzx cx, q#sreg#b
                  idiv cx
                  mov q0, ax
                  mov q1, dx
                  update_qbx_flags = 1
             endinsn

             ; word-sized operands
             insn sdivwq#sreg
                  xor rax, rax
                  xor rdx, rdx
                  mov ax, q0w
                  idiv q#sreg#w
                  mov q0, ax
                  mov q1, dx
                  update_qbx_flags = 1
             endinsn
        }


        ; bitwise and instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn andbq\#dreg\#q#sreg
                       and q\#dreg\#b, q#sreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn andwq\#dreg\#q#sreg
                       and q\#dreg\#w, q#sreg#w
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; bitwise or instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn orbq\#dreg\#q#sreg
                       or q\#dreg\#b, q#sreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn orwq\#dreg\#q#sreg
                       or q\#dreg\#w, q#sreg#w
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; bitwise not instructions
        rept QBX_NUM_REGISTERS dreg:0 {
                  ; byte-sized operands
                  insn invbq#dreg
                       not q#dreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn invwq#dreg
                       not q#dreg#w
                       update_qbx_flags = 1
                  endinsn

        }

        ; bitwise xor instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn xorbq\#dreg\#q#sreg
                       xor q\#dreg\#b, q#sreg#b
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn xorwq\#dreg\#q#sreg
                       xor q\#dreg\#w, q#sreg#w
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; shift left instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn shlbq\#dreg\#q#sreg
                       movzx rcx, q#sreg
                       shl q\#dreg\#b, cl
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn shlwq\#dreg\#q#sreg
                       movzx rcx, q#sreg
                       shl q\#dreg\#w, cl
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; shift right instructions
        rept QBX_NUM_REGISTERS sreg:0 {
             rept QBX_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn shrbq\#dreg\#q#sreg
                       movzx rcx, q#sreg
                       shr q\#dreg\#b, cl
                       update_qbx_flags = 1
                  endinsn

                  ; word-sized operands
                  insn shrwq\#dreg\#q#sreg
                       movzx rcx, q#sreg
                       shr q\#dreg\#w, cl
                       update_qbx_flags = 1
                  endinsn

             \}
        }

        ; unconditional jump to indirect address.
        insn jui
             mov qipw, q0
        endinsn

        ; unconditional jump to direct address.
        insn jud
             movzx rcx, word [qbx_mem + qip]
             mov qipw, cx
        endinsn

        ; convenience macro for defining conditional jump insn impls.
        macro _define_cond_jump cc* {
              insn j#cc#i
                   cmov#cc qipw, q0
              endinsn

              ; note that the impl for conditional jump to direct address
              ; needs to advance the insn ptr ONLY if the condition is not
              ; fulfilled. to do this, we use x86 setCC with a negated
              ; condition, multiply result by 2 and add it to the insn ptr
              ; at the end.
              insn j#cc#d
                   movzx rcx, word [qbx_mem + qip]
                   setn#cc dl
                   cmov#cc qipw, cx
                   shl     dl, 1
                   add     qipw, dx
              endinsn

              ; analogous implementations for the negative case.

              insn jn#cc#i
                   cmovn#cc qipw, q0
              endinsn

              insn jn#cc#d
                   movzx rcx, word [qbx_mem + qip]
                   set#cc dl
                   cmovn#cc qipw, cx
                   shl     dl, 1
                   add     qipw, dx
              endinsn
        }

        _define_cond_jump z
        _define_cond_jump a
        _define_cond_jump b
        _define_cond_jump g
        _define_cond_jump l
        _define_cond_jump ae
        _define_cond_jump be
        _define_cond_jump ge
        _define_cond_jump le

        ; call procedure at indirect address.
        insn jcalli
             sub qsp, 2
             mov word [qbx_mem + qsp], qipw
             mov qipw, q0
        endinsn

        ; call procedure at direct address.
        insn jcalld
             sub qsp, 2
             mov word [qbx_mem + qsp], qipw
             movzx rcx, word [qbx_mem + qip]
             mov qipw, cx
        endinsn

        ; return
        insn return
             mov qipw, word [qbx_mem + qsp]
             add qsp, 2
        endinsn

     insn yld
             ; save QBX state before handling yield event.
             pushfq   ; save flags that haven't been committed to qflags yet.
             push q0
             push q1
             push q2
             push q3
             movzx rcx, word [qbx_mem + qip]  ; read yield code into rcx.
             add qip, 2                       ; advance ip.
             push qip                         ; save ip.
             push qsp
             push qflags
             ; find appropriate handler.
             cmp rcx, 0x01
             je yld_screenupd
             cmp rcx, 0x02
             je yld_sleep
        yld_debugbreak:
             ; YIELD CODE 0x00 -- debug break.
             ; this is also triggered when no other matching handler is found.
             int3
             jmp yld_return
        yld_screenupd:
            ; YIELD CODE 0x01 -- screen update.
            ; q0 has pointer to screen area in memory;
            ; q1 has width/height of updated rect;
            ; q2 has X/Y coords of upper left corner of updated rect.
            add r12, qbx_mem
            xor rax, rax
            mov bx, r13w
            mov ah, bl
            shl rax, 8
            mov al, bh
            mov bx, q2
            and bx, 0xff00
            shr bx, 8
            mov word [screen_rect.Left], bx
            and q2, 0x00ff
            mov word [screen_rect.Top], q2
            call64 [WriteConsoleOutputA], [con_bbuf], r12, rax, 0, screen_rect
            call64 [SetConsoleActiveScreenBuffer], [con_bbuf]
            mov r10, [con_bbuf]
            mov r11, [con_fbuf]
            mov [con_bbuf], r11
            mov [con_fbuf], r10
            xor r12, r12
            jmp yld_return
        yld_sleep:
            ; YIELD CODE 0x02 -- sleep.
            ; q0 contains the number of milliseconds to sleep.
            movzx rcx, q0
            call64 [Sleep], rcx
            jmp yld_return
        yld_return:
             ; restore QBX state.
             pop qflags
             pop qsp
             pop qip
             pop q3
             pop q2
             pop q1
             pop q0
             popfq
        endinsn

     tiny_insns define_jmp_table, qbx_jmp_table

        update_flags_advance:
                ; commit the current set of flags to the qflags register and
                ; proceed to the next insn.
                lahf
                mov qflags, rax
                jmp advance



        
usage_error:
    mov edi, 2
    lea rsi, [msg_usage]
    mov edx, msg_usage_len
    jmp print_error


open_error:
    mov edi, 1
    lea rsi, [msg_open_error]
    mov edx, msg_open_error_len
    jmp print_error


read_error:
    ; Close the file before reporting the error.
    mov eax, 3
    mov rdi, r12
    syscall

    mov edi, 1
    lea rsi, [msg_read_error]
    mov edx, msg_read_error_len
    jmp print_error


too_large:
    mov eax, 3
    mov rdi, r12
    syscall

    mov edi, 1
    lea rsi, [msg_too_large]
    mov edx, msg_too_large_len
    jmp print_error


print_error:
    ; Save exit status while printing.
    mov r8d, edi

    mov eax, 1
    mov edi, 2
    syscall

    mov eax, 60
    mov edi, r8d
    syscall


success:
    mov eax, 60
    xor edi, edi
    syscall