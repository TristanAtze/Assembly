; fib_bench.asm — Count how many Fibonacci numbers we can generate in ~1s.
; Linux x86_64, NASM syntax, no libc (direct syscalls).
; Outputs ONLY the count (decimal) + newline.
; Fibonacci computed modulo 2^64 (wrap-around). That's fine for throughput counting.

BITS 64
default rel

%define SYS_read           0
%define SYS_write          1
%define SYS_clock_gettime  228
%define SYS_exit           60

%define CLOCK_MONOTONIC    1
%define CHECK_INTERVAL     1048576        ; check time every N iterations

SECTION .data
nl:         db 10

SECTION .bss
ts_start:   resq 2                        ; struct timespec {sec, nsec}
ts_now:     resq 2
end_sec:    resq 1
end_nsec:   resq 1
num_buf:    resb 32                       ; for decimal printing

SECTION .text
global _start

; ------------------------------------------------------------
; write(ptr=rsi, len=rdx)
; ------------------------------------------------------------
write:
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; ------------------------------------------------------------
; print_u64(rax=value)  -- prints decimal + '\n'
; clobbers: rbx, rcx, rdx, rsi, rdi, r8, r10
; ------------------------------------------------------------
print_u64:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rbx, 10

    ; Special case zero
    test rax, rax
    jnz .convert
    mov byte [num_buf], '0'
    mov rsi, num_buf
    mov rdx, 1
    call write
    ; newline
    mov rsi, nl
    mov rdx, 1
    call write
    jmp .done

.convert:
    ; Build digits in reverse from end of buffer
    lea r10, [num_buf + 32]           ; end pointer (one past last)
    mov r8, r10                       ; cursor
.conv_loop:
    xor rdx, rdx
    div rbx                           ; RDX:RAX / 10 -> RAX=quotient, RDX=remainder
    add dl, '0'
    dec r8
    mov [r8], dl
    test rax, rax
    jnz .conv_loop

    ; Write digits [r8, r10)
    mov rsi, r8
    mov rdx, r10
    sub rdx, r8
    call write
    ; newline
    mov rsi, nl
    mov rdx, 1
    call write

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------
; _start
; ------------------------------------------------------------
_start:
    ; Get start time
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_MONOTONIC
    mov rsi, ts_start
    syscall

    ; Compute deadline = start + 1 second
    mov rax, [ts_start]               ; start sec
    inc rax
    mov [end_sec], rax
    mov rax, [ts_start + 8]           ; start nsec
    mov [end_nsec], rax

    ; Fibonacci state and counter
    xor r8, r8                        ; a = 0
    mov r9, 1                         ; b = 1
    xor r11, r11                      ; count = 0

.loop_chunk:
    mov rcx, CHECK_INTERVAL
.loop_iter:
    ; t = a + b (mod 2^64)
    lea r10, [r8 + r9]
    mov r8, r9
    mov r9, r10
    inc r11
    dec rcx
    jnz .loop_iter

    ; Time check
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_MONOTONIC
    mov rsi, ts_now
    syscall

    ; if now_sec > end_sec -> done
    mov r8, [ts_now]                  ; now sec
    mov rax, [end_sec]
    cmp r8, rax
    ja  .time_up
    jb  .loop_chunk

    ; equal secs -> compare nsec
    mov r9, [ts_now + 8]              ; now nsec
    mov rdx, [end_nsec]
    cmp r9, rdx
    jae .time_up
    jmp .loop_chunk

.time_up:
    mov rax, r11                      ; count
    call print_u64

    mov rax, SYS_exit
    xor rdi, rdi
    syscall
