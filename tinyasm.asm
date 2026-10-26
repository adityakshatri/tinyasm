format ELF64 executable 3
entry _start

include 'tinyasm_insn_helpers.asm'
include 'tinyasm_insn_list.asm'
include 'tinyasm_registers.asm'

tiny_insns define_icodes, 0


section '.data' data readable writeable
    file_desc rq 1
    filename db "dump.bin", 0

section 'text' segment readable writeable

    tiny_mem rb MEM_SIZE + 1
    filename rb 4096

    msg_usage db "Usage: tiny <bytecode-file>", 10
    msg_usage_len = $ - msg_usage

    msg_open_error db "tiny: cannot open input file", 10
    msg_open_error_len = $ - msg_open_error

    msg_read_error db "tiny: failed to read input file", 10
    msg_read_error_len = $ - msg_read_error

    msg_too_large db "tiny: program exceeds 16 KiB", 10
    msg_too_large_len = $ - msg_too_large

    msg_read_len db "Bytes read: "
    msg_read_len_len = $ - msg_read_len

    ; Buffer for the decimal byte count and newline.
    number_buffer rb 32

    program_size rq 1

section '.text' code readable executable

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

    ; Read up to MEM_SIZE + 1 bytes.
    ; The extra byte detects oversized programs.
    xor eax, eax
    mov rdi, r12
    lea rsi, [tiny_mem]
    mov edx, MEM_SIZE + 1
    syscall

    test rax, rax
    js read_error

    ; Reject programs larger than 16 KiB.
    cmp rax, MEM_SIZE
    ja too_large

    ; Preserve the actual number of bytes read.
    mov [program_size], rax

    ; Print "Bytes read: "
    mov eax, 1
    mov edi, 1
    lea rsi, [msg_read_len]
    mov edx, msg_read_len_len
    syscall

    ; Convert byte count to decimal.
    mov rax, [program_size]
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
          ; prep for execution.
          xor t0, t0
          xor t1, t1
          xor t2, t2
          xor t3, t3
          xor tip, tip
          xor rdi, rdi
          mov tsp, MEM_SIZE - 1
          if defined(BUILD_MODE_DEBUG)
               int3         ; breakpoint for the debugger
          end if

    advance:
          mov di,word[tiny_mem + tip]
          add tip, 2
          movzx r10, word [tiny_jmp_table + rdi * 2]
          add r10, insn_base
          mov rax, flags
          sahf
          jmp r10

    ;Temporary endpoint: loading succeeded.
    ;CPU initialization and dispatch go here.
    insn_base:

    insn noop:
        nop
    end insn

    insn halt
        cmp[arg_ptr], 3
        jl quit
        mov r10,[arg_ptr]
        mov rdc, tword [r10+16]
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
               mov rsi, tiny_mem        ; buffer address
               mov rdx, MEM_SIZE    ; number of bytes
               syscall

               ;dump registers to file
               mov word [tiny_mem + 0],  t0
               mov word [tiny_mem + 2],  t1
               mov word [tiny_mem + 4],  t2
               mov word [tiny_mem + 6],  t3
               mov word [tiny_mem + 8],  tip
               mov word [tiny_mem + 10], tsp
               mov word [tiny_mem + 12], tflags

               mov rax, 1          ; syscall: write
               mov rdi, [file_desc]; file descriptor
               mov rsi, tiny_mem        ; buffer address
               mov rdx, MEM_SIZE    ; number of bytes
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
            mov r##reg, [word [tiny_mem + tip]]
            add tip, 2
        end insn

        ;byte sized oprands
        insn moveibq#reg
            movzx r##reg, byte [tiny_mem + tip]
            add tip, 1
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
            mov rax, [word [tiny_mem + tip]]
            add tip, 2
            mov [tiny_mem + rax], r##reg
        end insn

        insn storebq#reg
            movzx rax, byte [tiny_mem + tip]
            add tip, 1
            mov [tiny_mem + rax], r##regb
        end insn
    }

    ;store value to address in t0
    rept 3 reg {
        ;word sized
        insn storewq#reg
            move word [tiny_mem + t0], t#reg
        end insn

        insn storebq#reg
            move byte [tiny_mem + t0], t#regb
        end insn
    }
     ; push word-sized value onto the stack.
    rept TINY_NUM_REGISTERS reg:0 {
        insn pushwq#reg
            sub tsp, 2
            mov word [tiny_mem + tsp + 1], t#reg
        end insn

        insn pushbq#reg
            sub tsp, 1
            mov byte [tiny_mem + tsp + 1], t#reg#b
        end insn
    }

    ; pop word-sized value from the stack.
    rept TINY_NUM_REGISTERS reg:0 {
        insn popwq#reg
            mov t#reg, word [tiny_mem + tsp + 1]
            add tsp, 2
        endinsn

        insn popbq#reg
            mov t#reg#b, byte [tiny_mem + tsp + 1]
            add tsp, 1
        endinsn
    }


        ; addition instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn addbq\#dreg\#t#sreg
                       add t\#dreg\#b, t#sreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn addwq\#dreg\#t#sreg
                       add t\#dreg\#w, t#sreg#w
                       update_flags = 1
                  endinsn

             \}
        }

        ; subtraction instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn subbq\#dreg\#t#sreg
                       sub t\#dreg\#b, t#sreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn subwq\#dreg\#t#sreg
                       sub t\#dreg\#w, t#sreg#w
                       update_flags = 1
                  endinsn

             \}
        }

        ; unsigned multiplication
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn mulbq\#dreg\#t#sreg
                       xor rax, rax
                       mov al, t\#dreg\#b
                       mul t#sreg#b
                       mov t\#dreg\#b, al
                       update_flags = 1
                  endinsn

                 ; word-sized operands
                 insn mulwq\#dreg\#t#sreg
                      xor rax, rax
                      mov ax, t\#dreg\#w
                      mul t#sreg#w
                      mov t\#dreg\#w, ax
                      update_flags = 1
                  endinsn
             \}
        }

        ; signed multiplication
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn smulbq\#dreg\#t#sreg
                       xor rax, rax
                       mov al, t\#dreg\#b
                       imul t#sreg#b
                       mov t\#dreg\#b, al
                       update_flags = 1
                  endinsn

                 ; word-sized operands
                 insn smulwq\#dreg\#t#sreg
                      imul t\#dreg\#w, t#sreg#w
                      update_flags = 1
                  endinsn
             \}
        }

        ; unsigned division
        rept 3 sreg {
             ; byte-sized operands
             insn divbq#sreg
                  xor dx, dx
                  xor ax, ax
                  mov ax, t0w
                  movzx cx, t#sreg#b
                  div cx
                  mov t0, ax
                  mov t1, dx
                  update_flags = 1
             endinsn

             ; word-sized operands
             insn divwq#sreg
                  xor rax, rax
                  xor rdx, rdx
                  mov ax, t0w
                  div t#sreg#w
                  mov t0, ax
                  mov t1, dx
                  update_flags = 1
             endinsn
        }

        ; signed division
        rept 3 sreg {
             ; byte-sized operands
             insn sdivbq#sreg
                  xor dx, dx
                  xor ax, ax
                  mov ax, t0w
                  movzx cx, t#sreg#b
                  idiv cx
                  mov t0, ax
                  mov t1, dx
                  update_flags = 1
             endinsn

             ; word-sized operands
             insn sdivwq#sreg
                  xor rax, rax
                  xor rdx, rdx
                  mov ax, t0w
                  idiv t#sreg#w
                  mov t0, ax
                  mov t1, dx
                  update_flags = 1
             endinsn
        }


        ; bitwise and instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn andbq\#dreg\#t#sreg
                       and t\#dreg\#b, t#sreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn andwq\#dreg\#t#sreg
                       and t\#dreg\#w, t#sreg#w
                       update_flags = 1
                  endinsn

             \}
        }

        ; bitwise or instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn orbq\#dreg\#t#sreg
                       or t\#dreg\#b, t#sreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn orwq\#dreg\#t#sreg
                       or t\#dreg\#w, t#sreg#w
                       update_flags = 1
                  endinsn

             \}
        }

        ; bitwise not instructions
        rept TINY_NUM_REGISTERS dreg:0 {
                  ; byte-sized operands
                  insn invbq#dreg
                       not t#dreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn invwq#dreg
                       not t#dreg#w
                       update_flags = 1
                  endinsn

        }

        ; bitwise xor instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn xorbq\#dreg\#t#sreg
                       xor t\#dreg\#b, t#sreg#b
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn xorwq\#dreg\#t#sreg
                       xor t\#dreg\#w, t#sreg#w
                       update_flags = 1
                  endinsn

             \}
        }

        ; shift left instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn shlbq\#dreg\#t#sreg
                       movzx rcx, t#sreg
                       shl t\#dreg\#b, cl
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn shlwq\#dreg\#t#sreg
                       movzx rcx, t#sreg
                       shl t\#dreg\#w, cl
                       update_flags = 1
                  endinsn

             \}
        }

        ; shift right instructions
        rept TINY_NUM_REGISTERS sreg:0 {
             rept TINY_NUM_REGISTERS dreg:0 \{
                  ; byte-sized operands
                  insn shrbq\#dreg\#t#sreg
                       movzx rcx, t#sreg
                       shr t\#dreg\#b, cl
                       update_flags = 1
                  endinsn

                  ; word-sized operands
                  insn shrwq\#dreg\#t#sreg
                       movzx rcx, t#sreg
                       shr t\#dreg\#w, cl
                       update_flags = 1
                  endinsn

             \}
        }

        ; unconditional jump to indirect address.
        insn jui
             mov tipw, t0
        endinsn

        ; unconditional jump to direct address.
        insn jud
             movzx rcx, word [tiny_mem + tip]
             mov tipw, cx
        endinsn

        ; convenience macro for defining conditional jump insn impls.
        macro _define_cond_jump cc* {
              insn j#cc#i
                   cmov#cc tipw, t0
              endinsn

              ; note that the impl for conditional jump to direct address
              ; needs to advance the insn ptr ONLY if the condition is not
              ; fulfilled. to do this, we use x86 setCC with a negated
              ; condition, multiply result by 2 and add it to the insn ptr
              ; at the end.
              insn j#cc#d
                   movzx rcx, word [tiny_mem + tip]
                   setn#cc dl
                   cmov#cc tipw, cx
                   shl     dl, 1
                   add     tipw, dx
              endinsn

              ; analogous implementations for the negative case.

              insn jn#cc#i
                   cmovn#cc tipw, t0
              endinsn

              insn jn#cc#d
                   movzx rcx, word [tiny_mem + tip]
                   set#cc dl
                   cmovn#cc tipw, cx
                   shl     dl, 1
                   add     tipw, dx
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
             sub tsp, 2
             mov word [tiny_mem + tsp], tipw
             mov tipw, t0
        endinsn

        ; call procedure at direct address.
        insn jcalld
             sub tsp, 2
             mov word [tiny_mem + tsp], tipw
             movzx rcx, word [tiny_mem + tip]
             mov tipw, cx
        endinsn

        ; return
        insn return
             mov tipw, word [tiny_mem + tsp]
             add tsp, 2
        endinsn

     insn yld
             ; save cpu state before handling yield event.
             pushfq   ; save flags that haven't been committed to tflags yet.
             push t0
             push t1
             push t2
             push t3
             movzx rcx, word [tiny_mem + tip]  ; read yield code into rcx.
             add tip, 2                       ; advance ip.
             push tip                         ; save ip.
             push tsp
             push tflags
             ; find appropriate handler.
             cmp rcx, 0x01
             cmp rcx, 0x02
             je yld_sleep
        yld_debugbreak:
             ; YIELD CODE 0x00 -- debug break.
             ; this is also triggered when no other matching handler is found.
             int3
             jmp yld_return
        yld_sleep:
            ; YIELD CODE 0x02 -- sleep.
            ; t0 contains the number of milliseconds to sleep.
            mov rax, 162
            syscall
        yld_return:
             ; restore register state.
             pop tflags
             pop tsp
             pop tip
             pop t3
             pop t2
             pop t1
             pop t0
             popfq
        endinsn

     tiny_insns define_jmp_table, tiny_jmp_table

        update_flags_advance:
                ; commit the current set of flags to the tflags register and
                ; proceed to the next insn.
                lahf
                mov tflags, rax
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