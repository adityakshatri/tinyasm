
format ELF64 executable 3
entry _start

QBX_MEM_SIZE = 1024 * 16

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
    ;Temporary endpoint: loading succeeded.
    ; QBX CPU initialization and dispatch go here.
    jmp success



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