; calc.asm - Minimal integer REPL calculator (+ - * / %) for Linux x86_64
; NASM syntax, no libc (direct syscalls). System V AMD64 ABI.
; Input format: "<int> <op> <int>" e.g., "12 + 34"
; Supports: + - * / % (signed 64-bit). Type 'exit' or 'quit' to leave.
; Limitations: no operator precedence, one binary op per line, integer only.
; Author: your ruthless mentor

BITS 64
default rel

%define SYS_read   0
%define SYS_write  1
%define SYS_exit   60

SECTION .data
prompt:        db "> ",0
banner:        db "x86_64 calc (+ - * / %) — integer only. Type 'exit' or 'quit'.",10,0
err_divzero:   db "error: division by zero",10,0
err_parse:     db "error: parse failed (format: <int> <op> <int>)",10,0
nl:            db 10,0

quit_kw:       db "quit",0
exit_kw:       db "exit",0

SECTION .bss
buf:           resb 512
parse_err:     resb 1

; temp buffers
num_buf:       resb 32            ; enough for int64 with sign

SECTION .text
global _start

; ---------------------------------------
; write_cstr(rdi=char*)
; ---------------------------------------
write_cstr:
    push rdi
    mov rsi, rdi
    xor rcx, rcx
.len_loop:
    cmp byte [rsi], 0
    je .len_done
    inc rsi
    jmp .len_loop
.len_done:
    mov rdx, rsi
    pop rsi            ; restore into rsi as ptr
    sub rdx, rsi       ; len = end - start
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; ---------------------------------------
; write_str(rsi=ptr, rdx=len)
; ---------------------------------------
write_str:
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; ---------------------------------------
; read_line -> returns RAX = bytes read, buf zero-terminated, newline stripped
; ---------------------------------------
read_line:
    mov rax, SYS_read
    mov rdi, 0
    mov rsi, buf
    mov rdx, 511
    syscall                      ; rax = n
    cmp rax, 0
    jle .done                    ; EOF or error
    ; zero-terminate & strip newline
    mov rcx, rax
    mov rbx, buf
.strip:
    cmp rcx, 0
    je .ensure0
    mov al, [rbx]
    cmp al, 10
    je .put0
    cmp al, 13
    je .put0
    inc rbx
    dec rcx
    jmp .strip
.put0:
    mov byte [rbx], 0
.ensure0:
    ; if no newline found, ensure last byte is zero
    ; already ensured by write above
.done:
    ret

; ---------------------------------------
; skip_spaces(rsi -> rsi at first non-space)
; ---------------------------------------
skip_spaces:
.skip:
    mov al, [rsi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 0
    je .ret
    ret
.adv:
    inc rsi
    jmp .skip
.ret:
    ret

; ---------------------------------------
; match_word(rsi, rdi=word) -> ZF=1 if matches word fully and next is 0 or space
; does not advance rsi
; ---------------------------------------
match_word:
    ; rsi points at candidate, rdi points at word
    push rsi
    push rdi
.mloop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp bl, 0
    je .end_word
    cmp al, bl
    jne .nomatch
    inc rsi
    inc rdi
    jmp .mloop
.end_word:
    ; ensure boundary: candidate char is 0 or whitespace
    mov al, [rsi]
    cmp al, 0
    je .ok
    cmp al, ' '
    je .ok
    cmp al, 9
    je .ok
    ; also allow newline already stripped, so 0 checked
    jmp .nomatch
.ok:
    pop rdi
    pop rsi
    xor eax, eax
    inc eax          ; set ZF=0? We'll manually return via flags not convenient; instead return 1 in RAX
    ret
.nomatch:
    pop rdi
    pop rsi
    xor eax, eax     ; return 0
    ret

; ---------------------------------------
; parse_int(rsi -> rsi advanced), returns:
;   RAX = value (signed 64)
;   sets [parse_err]=0 on success, 1 on error
; ---------------------------------------
parse_int:
    mov byte [parse_err], 0
    xor rax, rax
    xor r10d, r10d                ; sign = 0 (positive)

    ; optional sign
    mov al, [rsi]
    cmp al, '-'
    jne .check_plus
    mov r10b, 1                   ; sign = negative
    inc rsi
    jmp .after_sign
.check_plus:
    cmp al, '+'
    jne .after_sign
    inc rsi
.after_sign:

    ; parse digits
    xor rax, rax
    xor rcx, rcx
.digit_loop:
    mov al, [rsi]
    cmp al, '0'
    jb .end_digits
    cmp al, '9'
    ja .end_digits

    ; rax = rax*10 + (al - '0')
    mov r8, rax
    shl rax, 3
    lea rax, [rax + r8*2]
    sub al, '0'
    movzx edx, al                 ; use edx as temp (avoid rbx)
    add rax, rdx

    inc rcx
    inc rsi
    jmp .digit_loop

.end_digits:
    test rcx, rcx
    jnz .have_digits
    mov byte [parse_err], 1
    xor rax, rax
    ret

.have_digits:
    test r10b, r10b
    jz .ok
    neg rax
.ok:
    ret


; ---------------------------------------
; parse_op(rsi -> rsi advanced), returns AL=op, sets parse_err on error
; ---------------------------------------
parse_op:
    mov byte [parse_err], 0
    mov al, [rsi]
    cmp al, 0
    je .fail
    ; expect one of + - * / %
    cmp al, '+'
    je .take
    cmp al, '-'
    je .take
    cmp al, '*'
    je .take
    cmp al, '/'
    je .take
    cmp al, '%'
    je .take
    jmp .fail
.take:
    inc rsi
    ret
.fail:
    mov byte [parse_err], 1
    xor eax, eax
    ret

; ---------------------------------------
; print_signed_rax(rax=value)
; uses num_buf as temp; prints value + newline
; ---------------------------------------
print_signed_rax:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rdi, num_buf
    ; handle zero
    cmp rax, 0
    jne .not_zero
    mov byte [rdi], '0'
    mov rdx, 1
    mov rsi, rdi
    call write_str
    ; newline
    mov rsi, nl
    call write_cstr
    jmp .done
.not_zero:
    ; handle sign
    mov rbx, 0
    test rax, rax
    jge .abs_done
    neg rax
    mov rbx, 1
.abs_done:
    ; convert to string (reverse)
    mov rsi, rdi            ; rsi = start
    add rdi, 31             ; write from end backward
    mov byte [rdi], 0
    dec rdi
.conv_loop:
    xor rdx, rdx
    mov rcx, 10
    div rcx                 ; rax/10, rdx = remainder (0..9)
    add dl, '0'
    mov [rdi], dl
    dec rdi
    test rax, rax
    jne .conv_loop
    ; add sign if needed
    cmp rbx, 0
    je .no_sign
    mov byte [rdi], '-'
    jmp .have_str
.no_sign:
    inc rdi                 ; move to first digit
.have_str:
    ; rdi -> cstr, compute len
    mov rsi, rdi
    xor rcx, rcx
.clen:
    cmp byte [rsi], 0
    je .gotlen
    inc rsi
    jmp .clen
.gotlen:
    mov rdx, rsi
    sub rdx, rdi
    mov rsi, rdi
    call write_str
    ; newline
    mov rsi, nl
    call write_cstr
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ---------------------------------------
; _start: REPL
; ---------------------------------------
_start:
    ; print banner
    mov rdi, banner
    call write_cstr

.repl:
    ; prompt
    mov rdi, prompt
    call write_cstr

    ; read line
    call read_line
    cmp rax, 0
    jle .exit

    ; rsi = buf
    mov rsi, buf
    call skip_spaces

    ; check 'exit' / 'quit'
    mov rdi, exit_kw
    call match_word
    cmp eax, 1
    je .exit
    mov rdi, quit_kw
    call match_word
    cmp eax, 1
    je .exit

    ; parse: A
    call parse_int
    cmp byte [parse_err], 0
    jne .parse_fail
    mov r8, rax            ; A
    call skip_spaces

    ; op
    call parse_op
    cmp byte [parse_err], 0
    jne .parse_fail
    mov bl, al             ; op
    call skip_spaces

    ; B
    call parse_int
    cmp byte [parse_err], 0
    jne .parse_fail
    mov r9, rax            ; B
    call skip_spaces

    ; compute
    mov rax, r8
    cmp bl, '+'
    je .do_add
    cmp bl, '-'
    je .do_sub
    cmp bl, '*'
    je .do_mul
    cmp bl, '/'
    je .do_div
    cmp bl, '%'
    je .do_mod
    jmp .parse_fail

.do_add:
    add rax, r9
    jmp .print
.do_sub:
    sub rax, r9
    jmp .print
.do_mul:
    imul rax, r9
    jmp .print
.do_div:
    cmp r9, 0
    je .divzero
    cqo
    idiv r9               ; rax=quotient
    jmp .print
.do_mod:
    cmp r9, 0
    je .divzero
    cqo
    idiv r9               ; rdx=remainder
    mov rax, rdx
    jmp .print

.divzero:
    mov rdi, err_divzero
    call write_cstr
    jmp .repl

.parse_fail:
    mov rdi, err_parse
    call write_cstr
    jmp .repl

.print:
    call print_signed_rax
    jmp .repl

.exit:
    mov rax, SYS_exit
    xor rdi, rdi
    syscall
