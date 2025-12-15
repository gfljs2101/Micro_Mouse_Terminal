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
    imul ax, 64 ; inode size = 64 bytes
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
