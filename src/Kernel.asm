[BITS 16]
[ORG 0x0000]    ; Kernel is loaded at 0x8000:0000 by the bootloader

start:
    mov [kernel_boot_drive], dl ; Save boot drive number from bootloader
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
    push ax
    push cx
    push di
    push es
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
    pop es
    pop di
    pop cx
    pop ax
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
; Print newline
; -----------------------------
print_newline:
    push ax
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    pop ax
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
    jne .check_ls
    call shutdown_computer
    ret

.check_ls:
    mov si, input_buf
    mov di, cmd_ls
    call strcmp
    cmp ax, 0
    jne .unknown
    call list_root_directory
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
; Data section
; -----------------------------
msg_welcome      db 13,10,"Micro Mouse Terminal by LevelPack1218",13,10,0
msg_press_key    db 13,10,"Press any key to continue...",13,10,0

prompt           db 13,10,"MMT> ",0
msg_help         db 13,10,"Commands: help, cls, reboot, shutdown, ls",13,10,0
msg_unknown      db 13,10,"Unknown command",13,10,0

cmd_help         db "help",0
cmd_cls          db "cls",0
cmd_reboot       db "reboot",0
cmd_shutdown     db "shutdown",0
cmd_ls           db "ls",0

input_buf        times 128 db 0

; Variables for LPFS
kernel_boot_drive db 0
fs_buffer        times 512 db 0

; LevelPackFileSystem (LPFS)
bits 16

;
; Constants
;
FS_MAGIC equ 0x4C504653 ; "LPFS"
SUPERBLOCK_SECTOR   equ 6
INODE_TABLE_SECTOR  equ 7
ROOT_DIR_SECTOR     equ 20 ; Root directory is in the first data block

;
; Data Structures
;

; Superblock: Contains metadata about the file system
superblock:
    .magic_number dd FS_MAGIC
    .total_blocks dd 0
    .inode_blocks dd 0
    .data_blocks dd 0
    .block_size dw 512

; Inode: Represents a file or directory (padded to 64 bytes)
inode:
    .mode dw 0 ; File type and permissions
    .size dd 0
    .pointers times 14 dd 0 ; Direct pointers to data blocks (56 bytes)
    .padding times 2 db 0 ; Pad to 64 bytes

; Directory Entry (32 bytes)
dir_entry:
    .inode_num dw 0
    .name times 30 db 0

; ------------------------------------------------------------------
; read_sectors
; Reads sectors from the disk.
; IN:
;   - al: Number of sectors to read
;   - cx: Starting sector number (LBA)
;   - es:bx: Destination buffer
; OUT:
;   - carry flag set on error
; Clobbers: ax, dx, si
;------------------------------------------------------------------
read_sectors:
    push cx

    ; Convert LBA (in cx) to CHS for BIOS
    mov ax, cx ; LBA in ax
    xor dx, dx
    mov si, 18 ; Sectors per track
    div si     ; ax = LBA / 18, dx = LBA % 18
    inc dx     ; dx = sector number (1-based)
    mov cl, dl ; Sector number -> cl

    xor dx, dx
    mov si, 2  ; Number of heads
    div si     ; ax = (LBA / 18) / 2 = cylinder, dx = (LBA / 18) % 2 = head
    mov ch, al ; Cylinder -> ch
    mov dh, dl ; Head -> dh

    ; Retry loop
    mov si, 3
.retry:
    mov dl, [kernel_boot_drive] ; Get boot drive from kernel's variable
    mov ah, 0x02                ; BIOS read function
    int 0x13
    jnc .success ; If no error, we are done

    ; Error occurred, reset disk system and retry
    xor ax, ax
    int 0x13
    dec si
    jnz .retry

.success:
    pop cx
    ret ; Carry flag is set by int 0x13 on error, cleared on success

; ------------------------------------------------------------------
; find_file_in_root
; Searches for a file in the root directory.
; IN:
;   - si: Pointer to null-terminated filename string
; OUT:
;   - ax: inode number if found, 0 otherwise.
;   - carry flag set on error or not found
; Clobbers: ax, bx, cx, dx, si, di, bp
;------------------------------------------------------------------
find_file_in_root:
    mov ax, cs
    mov es, ax
    mov bx, fs_buffer

    mov al, 1 ; Read one sector for the root directory
    mov cx, ROOT_DIR_SECTOR
    call read_sectors
    jc .error ; Disk error

    mov bp, fs_buffer
    mov cx, 16 ; 16 entries in the sector
.search_loop:
    cmp cx, 0
    je .not_found ; If we've checked all entries, it's not here

    push si ; Preserve filename pointer for this entry

    mov ax, [bp] ; Get inode number
    test ax, ax
    jz .no_match ; Skip if inode is 0 (unused entry)

    ; Now compare the filename
    mov di, bp
    add di, 2 ; DI points to the name in the directory entry
.compare_loop:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .no_match ; Mismatch

    test al, al ; End of string?
    je .found ; Both are null, it's a match

    inc si
    inc di
    jmp .compare_loop

.no_match:
    pop si ; Restore filename pointer for the next iteration
    add bp, 32 ; Move to the next directory entry
    dec cx
    jmp .search_loop

.not_found:
.error:
    stc
    mov ax, 0
    ret

.found:
    pop si ; Balance the stack
    mov ax, [bp] ; Return the inode number in ax
    clc
    ret

; ------------------------------------------------------------------
; read_file
; Reads the first block of a file. (Simplified)
; IN:
;   - ax: inode number of the file
;   - es:bx: destination buffer
; OUT:
;   - carry flag set on error
; Clobbers: ax, cx, dx, si
;------------------------------------------------------------------
read_file:
    push bx
    push es

    ; Read inode table
    mov ax, cs
    mov es, ax
    mov bx, fs_buffer
    mov al, 1 ; Read one sector
    mov cx, INODE_TABLE_SECTOR
    call read_sectors

    pop es
    pop bx
    jc .read_error

    ; Calculate inode position in buffer. inode numbers start from 1.
    dec ax
    ; Multiply by 64 using shifts for 8086 compatibility
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    mov si, ax

    ; Get the first data block pointer from the inode (offset 6: mode(2) + size(4))
    mov cx, [fs_buffer + si + 6]

    ; Read the data block into the destination buffer
    mov al, 1
    call read_sectors
    jc .read_error

    clc
    ret
.read_error:
    stc
    ret

; ------------------------------------------------------------------
; list_root_directory
; Reads the root directory and prints the names of all files.
; IN:
;   - None
; OUT:
;   - carry flag set on disk error
; Clobbers: ax, bx, cx, si, bp
;------------------------------------------------------------------
list_root_directory:
    mov ax, cs
    mov es, ax
    mov bx, fs_buffer

    mov al, 1 ; Read one sector for the root directory
    mov cx, ROOT_DIR_SECTOR
    call read_sectors
    jc .error ; Disk error

    mov bp, fs_buffer
    mov cx, 16 ; 16 entries in the root directory sector
.list_loop:
    push cx
    mov ax, [bp] ; Get inode number
    or ax, ax
    jz .skip_entry ; Skip if inode is 0 (unused)

    ; Inode is valid, print the filename
    push bp
    add bp, 2 ; Point to name field in dir_entry
    mov si, bp
    call print_string ; Assumes print_string is in kernel.asm
    pop bp
    call print_newline ; Assumes print_newline is in kernel.asm

.skip_entry:
    add bp, 32 ; Move to the next directory entry
    pop cx
    loop .list_loop

    clc ; Success
    ret

.error:
    stc ; Error
    ret

times 8192-($-$$) db 0
