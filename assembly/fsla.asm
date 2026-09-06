[BITS 16]
[ORG 0x2000]
[CPU 286]
jmp code
db 0xFF     ; just to separate the start JMP '0xEB' from the FSLA Table's JMPs
;__________________________________
; code
FSLA_table:
    jmp read_file       ; OFFSET 0x03 ;
    jmp write_file      ; OFFSET 0x06 ;
    jmp search_file     ; 0FFSET 0x09 ;
    jmp DIR_cmd         ; OFFSET 0x0C ;
    jmp rem_file        ; OFFSET 0x0F ;

; File System Layout:
;
;   [Filename - 11 bytes, OFFSET 0x00 - 0x0A]
;   [Cluster - 2 Bytes, OFFSET 0x0B - 0x0C]
;   [Reserved - OFFSET 0x0F] 
;   16 bytes for directory entry
;   only 1 word for FAT clusters (only 2296 Clusters)
;   64 max root directory files.
;

code:
    xor ax, ax
    mov es, ax
    mov ds, ax

mov si, data0
int 0x62
mov si, data1
int 0x62
mov si, data2
int 0x62
mov si, data3
int 0x62

load_FAT:
    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    mov ax, 5
    int 0x60
    mov bx, 0x4200
    mov ax, 6
    int 0x60
    mov bx, 0x4400
    mov ax, 7
    int 0x60
    mov bx, 0x4600
    mov ax, 8
    int 0x60
    mov bx, 0x4800
    mov ax, 9
    int 0x60
    mov bx, 0x4A00
    mov ax, 10
    int 0x60
    mov bx, 0x4C00
    mov ax, 11
    int 0x60
    mov bx, 0x4E00
    mov ax, 12
    int 0x60
    mov bx, 0x5000
    mov ax, 13
    int 0x60

load_ROOT:
    xor ax, ax
    mov es, ax
    mov bx, 0x5200
    mov ax, 14
    int 0x60
    mov bx, 0x5400
    mov ax, 15
    int 0x60

mov si, target_file
call far 0x0000:0x2009
mov dx, 0x1000
mov es, dx
call far 0x0000:0x2003
jmp 0x1000:0x0000

target_file db "KERNEL  BIN"

data0 db "FSLA File system 2.0 ", 0
data1 db "____________________", 0x0A, 0x0D, 0x0A, 0x0D, 0x0A, 0x0D, 0x00
data2 db "On Your Marks.. Boot!", 0x00
data3 db "Oh well, that was awkward...", 0x00

;__________________________________
; Vectors

;__________________
;__________________
read_file:
    ; Input:
    ;       AX = Starting Cluster
    ;       ES =  File Segment
    ; Output:
    ;       ES:BX Loaded clusters, Max File size is 64KB~
    xor dx, dx
    mov ds, dx
    mov si, 0x4000 ; SI = FAT Buffer
    mov dx, 0 ; Cluster Offset

.loop:
    mov si, 0x4000 ; SI = FAT Buffer
    shl ax, 1

    add si, ax
    mov bx, word [ds:si]

    push bx
    push ax

    mov bx, 0x0000
    add bx, dx

    xor ax, ax
    mov ax, si
    sub ax, 0x4000
    shr ax, 1
    add ax, 16  ; Data Area starts at LBA 16
    int 0x60

    pop ax
    pop bx

    cmp bx, 0xFFFF
    je .success
    cmp bx, 0x0000
    je .correrror
    add dx, 512
    cmp dx, 63488
    jae .memerror
    mov ax, bx
    jmp .loop
.success:
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    retf
.memerror:
    mov si, .merror
    int 0x62
    retf
.merror db "MEMFAULT_FS: File is way too large to be loaded! (64KB~)", 0x00

.correrror:
    mov si, .cerror
    int 0x62
    retf
.cerror db "FAT_FAULT_ERROR: Tried to load an empty cluster!", 0x00




;__________________
;__________________
write_file:
    ; Input:
    ;   DS:SI = Filename
    ;   ES    = Data Buffer  
    ;   AX    = File size
    mov word [cs:.og_stack], sp
    mov word [cs:.og_seg], ds
    mov word [cs:.og_off], si
    mov word [cs:.file_size], ax
    mov di, 0x0000
.calcx:
    mov bx, 512
    xor dx, dx
    mov cx, 63488 ; Max User-Generated file size
    cmp ax, cx
    jae .serror
    div bx
    cmp dx, 0
    je .go
    inc ax
.go:
    mov bp, ax
.free:
    xor ax, ax
    mov ds, ax
    mov si, 0x4000
    mov cx, 2296
    call .find 
    push si
    push si
    jmp .save_cluster
    
.find:
    cmp word [ds:si], 0x0000
    je .fdone
    add si, 2
    loop .find
    jmp .nerror
.fdone:
    ret


.nerror:
    xor ax, ax
    mov ds, ax
    mov si, .nerr
    int 0x62
    mov sp, word [cs:.og_stack]
    retf
.nerr db "Maximum drive size exceeded! cannot write a new file.", 0x00

.serror:
    xor ax, ax
    mov ds, ax
    mov si, .serr
    int 0x62
    mov sp, word [cs:.og_stack]
    retf
.serr db "File is too large to write! (64KB+).", 0x00
.save_cluster:
    mov dx, si    ; DX = Start Cluster
    sub dx, 0x4000
    shr dx, 1
    mov word [cs:.start_cluster], dx
.execute:
    mov dx, si    ; DX = Target Cluster
    dec bp

    mov ax, dx
    sub ax, 0x4000
    shr ax, 1
    add ax, 16
    push bx
    mov bx, di
    int 0x61
    pop bx

    cmp bp, 0
    je .finished_next

    pop si
    push ax
    push es
    push di
    mov di, si
    xor ax, ax
    mov es, ax
    add si, 2
    mov ax, 0x51FE
    sub ax, si
    shr ax, 1
    mov cx, ax
    jcxz .nerror_short
    call .find
    mov dx, si
    sub dx, 0x4000
    shr dx, 1
    mov word [es:di], dx
    pop di
    pop es
    pop ax
    push si

    

    add di, 512
    jmp .execute
.nerror_short:
    xor ax, ax
    mov ds, ax
    mov si, .nerr_short
    int 0x62
    mov sp, word [cs:.og_stack]
    retf
.nerr_short db "Maximum drive size exceeded! cannot write a new file.", 0x00


.finished_next:
    pop si
    ; Quick Table Update
    mov word [ds:si], 0xFFFF
    ; Directory Entry code..
.DIR_find:
    mov cx, 64
    xor ax, ax
    mov es, ax
    mov di, 0x5200 ; ROOT DIRECTORY
.DIR_loop:
    cmp byte [es:di], 0x00 ; Check for Empty Root directory Entry
    je .last_write
    add di, 16
    loop .DIR_loop
.DIR_error:
    xor ax, ax
    mov ds, ax
    mov si, .direrror
    int 0x62
    mov sp, word [cs:.og_stack]
    retf
.last_write:
    mov si, word [cs:.og_off]
    mov ds, word [cs:.og_seg]

    xor ax, ax
    mov es, ax

    mov cx, 11
.DIR_loop2:
    mov al, [ds:si]
    mov [es:di], al
    inc si
    inc di
    loop .DIR_loop2

    mov ax, word [cs:.start_cluster]
    mov word [es:di], ax
    add di, 2
    mov ax, [cs:.file_size]
    mov word [es:di], ax

    xor ax, ax
    mov es, ax
    ; Save FAT / ROOT DIR on Disk
    mov ax, 5
    mov bx, 0x4000
    int 0x61
    mov ax, 6
    mov bx, 0x4200
    int 0x61
    mov ax, 7
    mov bx, 0x4400
    int 0x61
    mov ax, 8
    mov bx, 0x4600
    int 0x61
    mov ax, 9
    mov bx, 0x4800
    int 0x61
    mov ax, 10
    mov bx, 0x4A00
    int 0x61
    mov ax, 11
    mov bx, 0x4C00
    int 0x61
    mov ax, 12
    mov bx, 0x4E00
    int 0x61
    mov ax, 13
    mov bx, 0x5000
    int 0x61
    mov ax, 14
    mov bx, 0x5200
    int 0x61
    mov ax, 15
    mov bx, 0x5400
    int 0x61
    mov sp, word [cs:.og_stack]
    retf
.direrror db "Max Files for the directory exceeded!", 0x00
.start_cluster dw 0x0000
.file_size dw 0x0000
.og_seg dw 0x0000
.og_off dw 0x0000
.og_stack dw 0x0000
;__________________
;__________________

;__________________
;__________________

search_file:
    ; Input:
    ;       DS:SI = Filename (11 chars max)
    ; Output:
    ;       AX = File's Starting Cluster
    ;       BL = does it exists?
    ;       CX = File Size
    mov dx, 0 ; Files Counted | Max Files in root dir is 64
    mov cx, 11 ; File Name size
    xor ax, ax
    mov es, ax
    mov di, 0x5200
    push di
    push si
.loop:
    cmpsb
    jne .invalid
    loop .loop
.success:
    pop si
    pop di

    push di
    add di, 11 ; Get Starting Cluster
    xor ax, ax
    mov ax, word [es:di]
    pop di
    add di, 13 ; Get Size
    mov cx, word [es:di]
    mov bl, 0xFF
    retf
.invalid:
    pop si
    pop di
    mov cx, 11
    inc dx
    cmp dx, 64
    je .notfound
    add di, 16
    push di
    push si
    jmp .loop
.notfound:
    mov si, .emsg
    int 0x62
    retf
.emsg db "File Not Found!", 0x00

;__________________
;__________________


;__________________
;__________________

type_file:
    ; input:
    ;   DS:SI = Filename
    mov cx, 8
    mov ah, 0x0E
    mov bh, 0x00
.loop1:
    lodsb
    cmp al, 0x20
    je .reset
    cmp al, 0x00
    je .reset
    int 0x10
    loop .loop1
    jmp .mid
.mid:
    mov al, '.'
    int 0x10
    mov cx, 3
.loop2:
    lodsb
    int 0x10
    loop .loop2
.end:
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    ret
.reset:
    loop .loop1
    jmp .mid
;__________________
;__________________

;__________________
;__________________

DIR_cmd:
    mov bh, 0x00
    mov ah, 0x0E
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    xor ax, ax
    mov ds, ax
    ; Check Disk METADATA
    mov si, .oem
    int 0x62
    mov si, 0x7C02
    cmp [si], 0x00
    je .noem
    mov cx, 16
.oemloop:
    lodsb
    cmp al, 0x20
    je .deny
    cmp al, 0x00
    je .deny
    int 0x10
    loop .oemloop
    jmp .listf
.deny:
    loop .oemloop
    jmp .listf
.noem:
    mov si, .nooem
    int 0x62
    mov ah, 0x0E
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    jmp .listf
.nooem db "The Target Drive does not have a Name."
.oem db "Drive: ", 0x00
.listf:
    ; List Files
    mov ah, 0x0E
    mov al, '/'
    int 0x10
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    mov si, 0x5200 ; ROOT DIR
    mov cx, 64
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
.loop:
    cmp byte [si], 0x00   ; Empty Entry
    push si
    je .reset
    push cx
    call type_file
    pop cx
    pop si
    add si, 16
    loop .loop
    jmp .done
.reset:
    pop si
    add si, 16
    loop .loop
    jmp .done
.done:
    retf

;__________________
;__________________

rem_file:
    ; read_file and search_file fork

    ; Input:
    ;       DS:SI = Filename (11 chars max)
    ; Output:
    ;       Removes the file.
    mov dx, 0
    mov cx, 11
    xor ax, ax
    mov es, ax
    mov di, 0x5200
    push di
    push si
.looprem:
    cmpsb
    jne .invalid
    loop .looprem
.remsuccess:
    mov bh, 0x00
    mov ah, 0x0E
    mov al, '!' ; Prints a "!" when file found.
    int 0x10
    pop si
    pop di
    xor ax, ax
    mov es, ax
    mov byte [es:di], 0x00 
    add di, 11 ; Get Starting Cluster
    mov ax, word [es:di]
    jmp .read_file
.invalid:
    mov bh, 0x00
    mov ah, 0x0E
    mov al, '.' ; Prints a "." for every incompatible file.
    int 0x10
    pop si
    pop di
    mov cx, 11
    inc dx
    cmp dx, 64
    je .notfound
    add di, 16
    push di
    push si
    jmp .looprem
.notfound:
    mov si, .emsg
    int 0x62
    retf
.emsg db "File Not Found!", 0x00





.read_file:
    ; Input:
    ;       AX = Starting Cluster
    ; Output:
    ;       Just removes the file rootdir entry and FAT entries
    xor dx, dx
    mov ds, dx
    mov si, 0x4000 ; SI = FAT Buffer

.loop:
    push si
    shl ax, 1
    add si, ax ; si = current cluster
    mov bx, word [si] ; bx = next cluster

    cmp bx, 0xFFFF ; Check for last cluster
    je .success
    cmp bx, 0x0000
    je .correrror
    mov word [ds:si], 0x0000

    mov ax, bx
    pop si
    jmp .loop
.success:
    mov word [ds:si], 0x0000
    pop si
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    mov ax, 5
    int 0x61
    mov bx, 0x4200
    mov ax, 6
    int 0x61
    mov bx, 0x4400
    mov ax, 7
    int 0x61
    mov bx, 0x4600
    mov ax, 8
    int 0x61
    mov bx, 0x4800
    mov ax, 9
    int 0x61
    mov bx, 0x4A00
    mov ax, 10
    int 0x61
    mov bx, 0x4C00
    mov ax, 11
    int 0x61
    mov bx, 0x4E00
    mov ax, 12
    int 0x61
    mov bx, 0x5000
    mov ax, 13
    int 0x61
    mov bx, 0x5200
    mov ax, 14
    int 0x61
    mov bx, 0x5400
    mov ax, 15
    int 0x61

    retf

.correrror:
    pop si
    mov si, .cerror
    int 0x62
    retf
.cerror db "FAT_RM_FAULT_ERROR: Tried to remove an empty cluster! file might have been corrupted and disk space reduced.", 0x00
;__________________
;__________________

times 2046 - ($ - $$) db 0x90 ; NOP
jmp $                       ; Halts system in-case of uncontrolled flow of CS:IP