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
;   [Cluster - 1 Byte, OFFSET 0x0B - 0x0B]
;   [Reserved - OFFSET 0x0C - 0x0F] 
;   16 bytes for directory entry
;   only 1 byte for FAT clusters (only 255 Clusters)
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
    mov ax, 4
    int 0x60
load_ROOT:
    xor ax, ax
    mov es, ax
    mov bx, 0x4200
    mov ax, 5
    int 0x60
    mov bx, 0x4400
    mov ax, 6
    int 0x60

mov si, target_file
call far 0x0000:0x2009
mov dx, 0x1000
mov es, dx
call far 0x0000:0x2003
jmp 0x1000:0x0000

target_file db "KERNEL  BIN"

data0 db "FSLA File system 1.0 ", 0
data1 db "____________________", 0x0A, 0x0D, 0x0A, 0x0D, 0x0A, 0x0D, 0x00
data2 db "On Your Marks.. Boot!", 0x00
data3 db "Oh well, that was awkward...", 0x00

;__________________________________
; Vectors

;__________________
;__________________
read_file:
    ; Input:
    ;       AL = Starting Cluster
    ;       ES =  File Segment
    ; Output:
    ;       ES:BX Loaded clusters, Max File size is 64KB~
    xor dx, dx
    mov ds, dx
    mov si, 0x4000 ; SI = FAT Buffer
    mov dx, 0 ; Cluster Offset

.loop:
    push si

    add si, ax
    mov bl, [si]

    push bx
    push ax

    mov bx, 0x0000
    add bx, dx

    xor ax, ax
    mov ax, si
    xor ah, ah
    add ax, 16  ; Data Area starts at LBA 16
    int 0x60

    pop ax
    pop bx

    cmp bl, 0xFF
    je .success
    cmp bl, 0x00
    je .correrror
    add dx, 512
    cmp dx, 63488
    jae .memerror
    mov al, bl
    pop si
    jmp .loop
.success:
    pop si
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    retf
.memerror:
    pop si
    mov si, .merror
    int 0x62
    retf
.merror db "MEMFAULT_FS: File is way too large to be loaded! (64KB~)", 0x00

.correrror:
    pop si
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
    mov cx, 2048 ; Max User-Generated file size
    cmp ax, cx
    ja .serror
    div bx
    cmp dx, 0
    je .go
    inc ax
.go:
    mov bp, ax
.free:
    mov cx, 256
    xor ax, ax
    mov ds, ax
    mov si, 0x4000
    call .find 
    push si
    push si
    jmp .save_cluster
    
.find:
    cmp byte [si], 0x00
    je .fdone
    inc si
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
.serr db "File is too large to write! (2KB).", 0x00
.save_cluster:
    mov dx, si    ; DL = Start Cluster
    xor dh, dh    ; |__________________
    mov byte [cs:.start_cluster], dl
.execute:
    mov dx, si    ; DL = Target Cluster
    xor dh, dh    ; |__________________
    dec bp

    mov ax, dx
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
    inc si
    mov cx, 256
    call .find
    mov dx, si
    sub dx, 0x4000
    mov [es:di], dl
    pop di
    pop es
    pop ax
    push si

    

    add di, 512
    mov cx, 256
    mov si, 0x4000
    call .find
    jmp .execute

.finished_next:
    pop si
    ; Quick Table Update
    mov byte [ds:si], 0xFF
    ; Directory Entry code..
.DIR_find:
    mov cx, 64
    xor ax, ax
    mov es, ax
    mov di, 0x4200 ; ROOT DIRECTORY
.DIR_loop:
    cmp byte [di], 0x00 ; Check for Empty Root directory Entry
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

    mov al, [cs:.start_cluster]
    mov [es:di], al
    inc di
    mov ax, [cs:.file_size]
    mov word [es:di], ax

    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    ; Save FAT / ROOT DIR on Disk
    mov ax, 4
    int 0x61
    mov ax, 5
    mov bx, 0x4200
    int 0x61
    mov ax, 6
    mov bx, 0x4400
    int 0x61
    mov sp, word [cs:.og_stack]
    retf
.direrror db "Max Files for the directory exceeded!", 0x00
.start_cluster db 0x00
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
    ;       AL = File's Starting Cluster
    ;       BL = does it exists?
    ;       CX = File Size
    mov dx, 0 ; Files Counted | Max Files in root dir is 64
    mov cx, 11 ; File Name size
    xor ax, ax
    mov es, ax
    mov di, 0x4200
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
    mov al, [es:di]
    pop di
    add di, 12 ; Get Size
    mov cx, [es:di]
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
    mov si, 0x4200 ; ROOT DIR
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
    mov di, 0x4200
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
    xor ax, ax
    mov al, [es:di]
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
    ;       AL = Starting Cluster
    ; Output:
    ;       Just removes the file rootdir entry and FAT entries
    xor dx, dx
    mov ds, dx
    mov si, 0x4000 ; SI = FAT Buffer

.loop:
    push si

    add si, ax ; si = current cluster
    mov bl, [si] ; bl = next cluster

    cmp bl, 0xFF ; Check for last cluster
    je .success
    cmp bl, 0x00
    je .correrror
    mov byte [ds:si], 0x00

    mov al, bl
    pop si
    jmp .loop
.success:
    mov byte [ds:si], 0x00
    pop si
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    mov ax, 4
    int 0x61
    mov bx, 0x4200
    mov ax, 5
    int 0x61
    mov bx, 0x4400
    mov ax, 6
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

times 1534 - ($ - $$) db 0x90 ; NOP
jmp $                       ; Halts system in-case of uncontrolled flow of CS:IP