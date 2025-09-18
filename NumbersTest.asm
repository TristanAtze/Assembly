; stats.asm — Read N integers, store into array, print sum/avg/max/min.
; Linux x86_64, NASM syntax, no libc (direct syscalls).
; Average printed with up to 6 fractional digits (trim trailing zeros).
; Input examples:
;   Wie viele Zahlen willst du eingeben? 5
;   Zahl 1: 10
;   ...
; Limits: N in [1..4096], 64-bit signed integers. No overflow handling on sum.

BITS 64
default rel

%define SYS_read           0
%define SYS_write          1
%define SYS_exit           60

SECTION .data
; Prompts / labels
q_count:     db "Wie viele Zahlen willst du eingeben? ",0
q_num1:      db "Zahl ",0
q_num2:      db ": ",0

lbl_sum:     db 10,"Summe: ",0
lbl_avg:     db "Durchschnitt: ",0
lbl_max:     db "Groesste Zahl: ",0
lbl_min:     db "Kleinste Zahl: ",0

err_count:   db "Fehler: Bitte eine Zahl zwischen 1 und 4096 eingeben.",10,0
err_parse:   db "Fehler: Zahl ungueltig. Bitte erneut eingeben.",10,0

dot:         db ".",0
nl:          db 10

SECTION .bss
buf:         resb 512
parse_err:   resb 1

; number formatting buffers
num_buf:     resb 32
frac_buf:    resb 32               ; up to 32 decimals (we'll use 6)

; storage for values (array of int64)
arr:         resq 4096

SECTION .text
global _start

; ---------------- I/O helpers ----------------
; write_cstr(rdi=char*)
write_cstr:
    push rdi
    mov rsi, rdi
    xor rcx, rcx
  .len:
    cmp byte [rsi], 0
    je .got
    inc rsi
    jmp .len
  .got:
    mov rdx, rsi
    pop rsi
    sub rdx, rsi
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; write(rsi=ptr, rdx=len)
write:
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; read_line() -> RAX=bytes, buf zero-terminated (newline stripped)
read_line:
    mov rax, SYS_read
    mov rdi, 0
    mov rsi, buf
    mov rdx, 511
    syscall
    cmp rax, 0
    jle .done
    mov rcx, rax
    mov rbx, buf
  .scan:
    cmp rcx, 0
    je .z
    mov al, [rbx]
    cmp al, 10
    je .put0
    cmp al, 13
    je .put0
    inc rbx
    dec rcx
    jmp .scan
  .put0:
    mov byte [rbx], 0
  .z:
  .done:
    ret

; skip_spaces(rsi -> first non-space/tab)
skip_spaces:
  .s:
    mov al, [rsi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    ret
  .adv:
    inc rsi
    jmp .s

; parse_int(rsi -> rsi advanced), returns RAX=value, sets [parse_err]=0/1
; DOES NOT touch rbx (important).
parse_int:
    mov byte [parse_err], 0
    xor rax, rax
    xor r10d, r10d               ; sign flag 0=+, 1=-
    ; optional sign
    mov al, [rsi]
    cmp al, '-'
    jne .check_plus
    mov r10b, 1
    inc rsi
    jmp .after_sign
  .check_plus:
    cmp al, '+'
    jne .after_sign
    inc rsi
  .after_sign:
    xor rax, rax
    xor rcx, rcx                 ; digit count
  .loop:
    mov al, [rsi]
    cmp al, '0'
    jb .end
    cmp al, '9'
    ja .end
    ; rax = rax*10 + (al-'0')
    mov r8, rax
    shl rax, 3
    lea rax, [rax + r8*2]
    sub al, '0'
    movzx edx, al
    add rax, rdx
    inc rcx
    inc rsi
    jmp .loop
  .end:
    test rcx, rcx
    jnz .have
    mov byte [parse_err], 1
    xor rax, rax
    ret
  .have:
    test r10b, r10b
    jz .ok
    neg rax
  .ok:
    ret

; print signed integer in RAX, no newline
print_signed_no_nl:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rdi, num_buf
    ; zero?
    cmp rax, 0
    jne .notzero
    mov byte [rdi], '0'
    mov rsi, rdi
    mov rdx, 1
    call write
    jmp .done
  .notzero:
    mov rbx, 0
    test rax, rax
    jge .abs
    neg rax
    mov rbx, 1
  .abs:
    ; convert to reverse digits
    lea rsi, [num_buf + 31]
    mov byte [rsi], 0
    dec rsi
  .conv:
    xor rdx, rdx
    mov rcx, 10
    div rcx
    add dl, '0'
    mov [rsi], dl
    dec rsi
    test rax, rax
    jne .conv
    inc rsi
    cmp rbx, 0
    je .out
    dec rsi
    mov byte [rsi], '-'
  .out:
    ; write cstr at rsi
    ; compute len
    mov rdx, rsi
  .len2:
    cmp byte [rdx], 0
    je .len_done2
    inc rdx
    jmp .len2
  .len_done2:
    sub rdx, rsi
    call write
  .done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; print signed integer + newline
print_signed_ln:
    call print_signed_no_nl
    mov rsi, nl
    mov rdx, 1
    call write
    ret

; print unsigned in RAX, no newline (used for index)
print_u64_no_nl:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rbx, 10
    test rax, rax
    jnz .conv
    mov byte [num_buf], '0'
    mov rsi, num_buf
    mov rdx, 1
    call write
    jmp .done
  .conv:
    lea rdi, [num_buf + 32]
    mov rsi, rdi
  .loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jne .loop
    mov rdx, rdi
    sub rdx, rsi
    call write
  .done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; print_avg( RAX = sum (signed), RDI = count (positive) ) -> prints decimal + NL
; Up to 6 fractional digits, trims trailing zeros (and the dot if none).
print_avg:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10

    ; handle sign
    mov rbx, 0                 ; sign flag
    test rax, rax
    jge .sum_abs
    neg rax
    mov rbx, 1
  .sum_abs:
    ; integer part = floor(sum_abs / count), rem = sum_abs % count
    xor rdx, rdx
    div rdi                    ; unsigned div because rax is abs
    ; now rax=quot, rdx=rem
    cmp rbx, 0
    je .print_int
    ; print '-'
    mov byte [num_buf], '-'
    mov rsi, num_buf
    mov rdx, 1
    call write
  .print_int:
    ; print quotient (unsigned)
    call print_u64_no_nl

    ; if rem==0 -> newline and done
    test rdx, rdx
    jnz .frac
    mov rsi, nl
    mov rdx, 1
    call write
    jmp .done

  .frac:
    ; produce up to DIGITS=6 fractional digits into frac_buf
    mov rcx, 6                 ; digits
    mov r8, rdx                ; rem
    mov r9, 0                  ; count produced
  .frac_loop:
    ; r8 = r8 * 10
    mov rax, r8
    imul rax, rax, 10
    xor rdx, rdx
    div rdi                    ; rax=next digit, rdx=new rem
    mov r8, rdx
    ; store digit char
    mov dl, al
    add dl, '0'
    mov [frac_buf + r9], dl
    inc r9
    loop .frac_loop

    ; trim trailing zeros
    mov rcx, r9
    cmp rcx, 0
    je .no_frac
  .trim:
    dec rcx
    jl .no_frac
    mov al, [frac_buf + rcx]
    cmp al, '0'
    jne .have_frac
    jmp .trim
  .no_frac:
    ; all zeros -> just newline
    mov rsi, nl
    mov rdx, 1
    call write
    jmp .done
  .have_frac:
    inc rcx                    ; length = last_nonzero_idx+1

    ; print '.' then the digits
    mov rsi, dot
    call write_cstr            ; prints just '.'
    mov rsi, frac_buf
    mov rdx, rcx
    call write
    mov rsi, nl
    mov rdx, 1
    call write

  .done:
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ---------------- main ----------------
_start:
  ; ask for N
.ask_n:
    mov rdi, q_count
    call write_cstr
    call read_line
    mov rsi, buf
    call skip_spaces
    call parse_int
    cmp byte [parse_err], 0
    jne .bad_n
    mov r12, rax               ; N
    cmp r12, 1
    jb .bad_n
    cmp r12, 4096
    ja .bad_n
    jmp .have_n
  .bad_n:
    mov rdi, err_count
    call write_cstr
    jmp .ask_n
  .have_n:

    ; init sum/min/max
    xor r13, r13               ; sum = 0
    mov r14, 0x8000000000000000 ; max = INT64_MIN
    mov r15, 0x7FFFFFFFFFFFFFFF ; min = INT64_MAX

    xor rbx, rbx               ; i = 0

.loop_i:
    cmp rbx, r12
    jae .done_input

    ; Print "Zahl " (index+1) ": "
    mov rdi, q_num1
    call write_cstr
    mov rax, rbx
    inc rax
    call print_u64_no_nl
    mov rdi, q_num2
    call write_cstr

  .read_value:
    call read_line
    mov rsi, buf
    call skip_spaces
    call parse_int
    cmp byte [parse_err], 0
    je .ok_val
    mov rdi, err_parse
    call write_cstr
    jmp .read_value

  .ok_val:
    ; store into arr[i]
    mov [arr + rbx*8], rax

    ; sum += val
    add r13, rax

    ; if val > max -> max = val
    mov r8, rax
    cmp r8, r14
    jle .skip_max
    mov r14, r8
  .skip_max:

    ; if val < min -> min = val
    cmp r8, r15
    jge .skip_min
    mov r15, r8
  .skip_min:

    inc rbx
    jmp .loop_i

.done_input:
    ; blank line
    mov rsi, nl
    mov rdx, 1
    call write

    ; Summe
    mov rdi, lbl_sum
    call write_cstr
    mov rax, r13
    call print_signed_ln

    ; Durchschnitt
    mov rdi, lbl_avg
    call write_cstr
    mov rax, r13          ; sum
    mov rdi, r12          ; count
    call print_avg

    ; Groesste
    mov rdi, lbl_max
    call write_cstr
    mov rax, r14
    call print_signed_ln

    ; Kleinste
    mov rdi, lbl_min
    call write_cstr
    mov rax, r15
    call print_signed_ln

    ; exit(0)
    mov rax, SYS_exit
    xor rdi, rdi
    syscall
