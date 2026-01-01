[BITS 16]
[ORG 0x0000]    ; Kernel is loaded at 0x8000:0000 by the bootloader

start:
    call init_idt
    call init_fs
    call clear_screen
    call welcome_screen
    call clear_screen

main_loop:
    mov si, prompt
    call print_string
    call read_line
    call to_lowercase
    call handle_command
    jmp main_loop

; -----------------------------
; Welcome screen
; -----------------------------
welcome_screen:
    mov si, msg_welcome
.print_loop:
    lodsb
    or al, al
    jz .print_continue
    mov ah, 0x0E
    int 0x10
    jmp .print_loop

.print_continue:
    mov si, msg_press_key
.press_loop:
    lodsb
    or al, al
    jz .wait_key
    mov ah, 0x0E
    int 0x10
    jmp .press_loop

.wait_key:
    xor ah, ah
    int 0x16
    ret

; -----------------------------
; Clear screen
; -----------------------------
clear_screen:
    pusha
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov ah, 0x07
    mov al, ' '
    mov cx, 2000
.clear_loop:
    stosw
    loop .clear_loop

    mov ah, 0x02
    mov bh, 0x00
    mov dh, 0x00
    mov dl, 0x00
    int 0x10
    popa
    ret

; -----------------------------
; Print string
; -----------------------------
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

; -----------------------------
; Read line
; -----------------------------
read_line:
    mov si, input_buf
    xor cx, cx
.read_char:
    xor ah, ah
    int 0x16
    cmp al, 13
    je .done
    cmp al, 8
    jne .store_char
    cmp cx, 0
    je .read_char
    dec si
    dec cx
    mov ah, 0x0E
    mov al, 8
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 8
    int 0x10
    jmp .read_char
.store_char:
    mov [si], al
    inc si
    inc cx
    mov ah, 0x0E
    int 0x10
    jmp .read_char
.done:
    mov byte [si], 0
    ret

; -----------------------------
; To lowercase
; -----------------------------
to_lowercase:
    mov si, input_buf
.lower_loop:
    mov al, [si]
    or al, al
    jz .done
    cmp al, 'A'
    jb .skip
    cmp al, 'Z'
    ja .skip
    add al, 32
    mov [si], al
.skip:
    inc si
    jmp .lower_loop
.done:
    ret

; -----------------------------
; Command handler
; -----------------------------
handle_command:
    mov al, [input_buf]
    cmp al, 0
    je .empty_input

    mov si, input_buf
    mov di, cmd_help
    call strcmp
    cmp ax, 0
    jne .check_cls
    mov si, msg_help
    call print_string
    ret

.check_cls:
    mov si, input_buf
    mov di, cmd_cls
    call strcmp
    cmp ax, 0
    jne .check_reboot
    call clear_screen
    ret

.check_reboot:
    mov si, input_buf
    mov di, cmd_reboot
    call strcmp
    cmp ax, 0
    jne .check_shutdown
    call soft_reboot
    ret

.check_shutdown:
    mov si, input_buf
    mov di, cmd_shutdown
    call strcmp
    cmp ax, 0
    jne .try_com_file
    call shutdown_computer
    ret

.try_com_file:
    mov si, input_buf
    mov cx, 0xFFFF
    xor al, al
    repne scasb
    dec si
    cmp byte [si-1], 'm'
    jne .unknown
    cmp byte [si-2], 'o'
    jne .unknown
    cmp byte [si-3], 'c'
    jne .unknown
    cmp byte [si-4], '.'
    jne .unknown
    mov si, input_buf
    call parse_filename
    call find_file
    cmp ax, 0
    je .not_found
    mov bx, 0x9000
    mov es, bx
    mov di, 0x0100
    call load_file
    jmp 0x9000:0x0100

.not_found:
    mov si, msg_not_found
    call print_string
    ret

.empty_input:
    ret

.unknown:
    mov si, msg_unknown
    call print_string
    ret

; -----------------------------
; String compare
; -----------------------------
strcmp:
    xor ax, ax
.sc_loop:
    lodsb
    mov bl, [di]
    inc di
    cmp al, bl
    jne .neq
    or al, al
    jnz .sc_loop
    xor ax, ax
    ret
.neq:
    mov ax, 1
    ret

parse_filename:
    pusha
    mov di, filename
    mov al, ' '
    mov cx, 11
    rep stosb
    mov di, filename
.copy_name:
    lodsb
    or al, al
    jz .done
    cmp al, '.'
    je .copy_ext
    cmp di, filename + 8
    jae .find_dot
    cmp al, 'a'
    jb .upper
    cmp al, 'z'
    ja .upper
    sub al, 32
.upper:
    mov [di], al
    inc di
    jmp .copy_name
.find_dot:
    lodsb
    or al, al
    jz .done
    cmp al, '.'
    jne .find_dot
.copy_ext:
    mov di, filename + 8
.copy_ext_loop:
    lodsb
    or al, al
    jz .done
    cmp di, filename + 11
    jae .done
    cmp al, 'a'
    jb .upper2
    cmp al, 'z'
    ja .upper2
    sub al, 32
.upper2:
    mov [di], al
    inc di
    jmp .copy_ext_loop
.done:
    popa
    ret

; -----------------------------
; Soft reboot using BIOS warm reboot vector
; -----------------------------
soft_reboot:
    cli
    ; Set warm boot flag at 0x472 to 0x1234
    mov word [0x472], 0x1234
    ; Jump to BIOS start
    jmp 0xFFFF:0x0000
    ret

; -----------------------------
; Shutdown routine
; -----------------------------
shutdown_computer:
    cli
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    jc .halt
.halt:
    hlt
    jmp .halt

; -----------------------------
; Interrupts
; -----------------------------
init_idt:
    cli
    mov ax, 0
    mov es, ax
    mov word [es:0x20*4], int20_handler
    mov [es:0x20*4+2], cs
    sti
    ret

int20_handler:
    jmp main_loop

; -----------------------------
; Filesystem
; -----------------------------
init_fs:
    mov ax, [reserved_sectors]
    mov [root_dir_lba], ax
    mov bl, [num_fats]
    mov ax, [sectors_per_fat]
    mul bl
    add [root_dir_lba], ax
    mov ax, [root_entries]
    mov bx, 32
    mul bx
    div word [bytes_per_sector]
    mov [root_sectors], ax
    mov ax, [root_dir_lba]
    add ax, [root_sectors]
    mov [data_lba], ax
    ret

find_file:
    mov cx, [root_sectors]
    mov ax, [root_dir_lba]
.sector_loop:
    push cx
    push ax
    call lba_to_chs
    call read_sectors
    mov cx, [root_entries]
    mov di, buffer
.search_loop:
    push di
    push cx
    mov cx, 11
    mov si, filename
    rep cmpsb
    pop cx
    pop di
    je .found
    add di, 32
    loop .search_loop
    pop ax
    pop cx
    inc ax
    loop .sector_loop
    jmp .not_found
.found:
    mov ax, [di + 26]
    ret
.not_found:
    mov ax, 0
    ret

load_file:
    mov [cluster], ax
.load_loop:
    cmp ax, 0xFF8
    jnb .done
    mov ax, [cluster]
    sub ax, 2
    mul byte [sectors_per_cluster]
    add ax, [data_lba]
    call lba_to_chs
    call read_sectors
    mov si, buffer
    mov cx, [bytes_per_sector]
    rep movsb
    mov ax, [cluster]
    mov bx, 3
    mul bx
    mov bx, 2
    div bx
    add ax, [reserved_sectors]
    push es
    push di
    call lba_to_chs
    call read_sectors
    pop di
    pop es
    mov si, buffer
    add si, dx
    mov ax, [ds:si]
    test byte [cluster], 1
    jnz .odd
.even:
    and ax, 0x0FFF
    jmp .next
.odd:
    shr ax, 4
.next:
    mov [cluster], ax
    jmp .load_loop
.done:
    ret

; -----------------------------
; Disk I/O
; -----------------------------
read_sectors:
    pusha
    .retry:
        mov ah, 0x02
        mov al, 1
        mov ch, byte [track]
        mov cl, byte [sector]
        mov dh, byte [head]
        mov dl, 0
        mov bx, buffer
        int 0x13
        jnc .done
        call reset_disk
        jmp .retry
    .done:
        popa
        ret

reset_disk:
    pusha
    mov ah, 0x00
    mov dl, 0
    int 0x13
    popa
    ret

lba_to_chs:
    pusha
    xor dx, dx
    div word [sectors_per_track]
    mov byte [sector], dl
    inc byte [sector]
    xor dx, dx
    div word [heads_per_cylinder]
    mov byte [head], dl
    mov byte [track], al
    popa
    ret

; -----------------------------
; Data section
; -----------------------------
msg_welcome      db 13,10,"Micro Mouse Terminal by LevelPack1218",13,10,0
msg_press_key    db 13,10,"Press any key to continue...",13,10,0

prompt           db 13,10,"MMT> ",0
msg_help         db 13,10,"Commands: help, cls, reboot, shutdown",13,10,0
msg_unknown      db 13,10,"Unknown command",13,10,0
msg_not_found    db 13,10,"File not found",13,10,0

cmd_help         db "help",0
cmd_cls          db "cls",0
cmd_reboot       db "reboot",0
cmd_shutdown     db "shutdown",0

input_buf        times 128 db 0
buffer           times 512 db 0
filename         times 11 db 0
cluster          dw 0
root_dir_lba     dw 0
root_sectors     dw 0
data_lba         dw 0

bytes_per_sector   dw 512
sectors_per_cluster db 1
reserved_sectors   dw 1
num_fats           db 2
root_entries       dw 224
total_sectors      dw 2880
sectors_per_fat    dw 9
sectors_per_track  dw 18
heads_per_cylinder dw 2

track            db 0
head             db 0
sector           db 0

times 8192-($-$$) db 0
