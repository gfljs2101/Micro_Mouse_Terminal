[BITS 16]
[ORG 0x100]

main:
    mov si, msg_hello
    call print_string
    int 0x20 ; Terminate

print_string:
.next_char:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp .next_char
.done:
    ret

msg_hello db "Hello from a .com file!", 13, 10, 0
