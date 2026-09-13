[BITS 16]
[ORG 0x2000]
[CPU 286]
jmp short code_bridge
db 0xFF     ; just to separate the start JMP '0xEB' from the FSLA Table's JMPs
;__________________________________
; code
FSLA_table:
    jmp near read_file       ; OFFSET 0x03 ;
    jmp near write_file      ; OFFSET 0x06 ;
    jmp near search_file     ; 0FFSET 0x09 ;
    jmp near DIR_cmd         ; OFFSET 0x0C ;
    jmp near rem_file        ; OFFSET 0x0F ;

; File System Layout:
;
;   [Filename - 11 bytes, OFFSET 0x00 - 0x0A]
;   [Cluster - 2 Bytes, OFFSET 0x0B - 0x0C]
;   [Reserved - OFFSET 0x0F] 
;   16 bytes for directory entry
;   only 1 word for FAT clusters (only 2296 Clusters)
;   64 max root directory files.
;
data0 db "FSLA 3.0", 0x00
data1 db "________________________", 0x00
data2 db "All Set...", 0x00
data3 db "On Your Marks...", 0x00
data4 db "Boot!", 0x00 
data5 db "Erm.. that was awkward..", 0x00
code_bridge:
    jmp short code
load_FAT_and_ROOT:
    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    mov ax, 5
    mov cx, 11

.load_loop:
    int 0x60
    add bx, 512
    inc ax
    loop .load_loop
    ret
update_FAT_and_ROOT:
    xor ax, ax
    mov es, ax
    mov bx, 0x4000
    mov ax, 5
    mov cx, 11

.update_loop:
    int 0x61
    add bx, 512
    inc ax
    loop .update_loop
    ret

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
mov si, data4
int 0x62
mov si, data5
int 0x62
call load_FAT_and_ROOT
mov si, .targetfile
call far 0x0000:0x2009
push ax
mov ax, 0x1000
mov es, ax
pop ax
call far 0x0000:0x2003
jmp far 0x1000:0x0000
.targetfile db "KERNEL  BIN"

search_file:
    pusha
    call load_FAT_and_ROOT
    ; Input:
    ;       DS:SI = Filename (11 chars max)
    ; Output:
    ;       AX = File's Starting Cluster
    ;       BL = does it exists? (0xFF = Y | 0x00 = N)
    ;       CX = File Size

    ; Points to the Root directory.
    ;_
    push ax
    xor ax, ax
    mov es, ax
    mov di, 0x5200
    pop ax
    ;_
    cld
    mov cx, 11  ; 11 bytes for Filename
    mov dx, 64  ; 64 Root Entries Max
    push di
    push si
.search_loop:
    ; Loops onto the root directory entry until find a match
    ;_
    repe cmpsb
    jz .s_done
    ;_
.s_invalid:
    ; If Invalid, jumps to the next root dir entry or raises a fileNotFound error
    ;_
    pop si
    pop di
    dec dx
    cmp dx, 0
    je .fnferror
    mov cx, 11
    add di, 16
    push di
    push si
    jmp .search_loop
    ;_
.s_done:
    ; Read Docstring output details.
    ;_ 
    pop si
    pop di

    add di, 11
    mov ax, word [es:di]
    mov word [cs:.sd_sc], ax ; Starting Cluster
    add di, 2
    mov ax, word [es:di]
    mov word [cs:.sd_fs], ax ; File Size
    mov si, .sd_donestring
    int 0x62
    popa
    mov ax, word [cs:.sd_sc]
    mov cx, word [cs:.sd_fs]
    mov bl, 0xFF

    retf
    ;_
.sd_donestring db "Gotcha!", 0x00
.sd_sc dw 0x0000
.sd_fs dw 0x0000

.fnferror:
    ; Quits Search Operation due to file not found error.
    ;_
    mov si, .fnfstring
    int 0x62
    popa
    mov bl, 0x00
    retf
    ;_
.fnfstring db "err_fileNotFound", 0x00



;___________________________________________________________



DIR_cmd:
    ; Input: 
    ;   None
    ; Output:
    ;   lists all files in the root directory

    ; Prints the OEM Name
    ;_
    pusha
    call load_FAT_and_ROOT
    mov ax, 0x0000
    mov ds, ax
    mov es, ax

    mov si, 0x7C02
    mov cx, 16
    mov ah, 0x0E
    mov bl, 0x00
.oemloop:
    lodsb
    cmp al, 0x20
    je .skipadder
    int 0x10
    loop .oemloop
    jmp short .dirc
.skipadder:
    loop .oemloop
    jmp short .dirc
    ;_
.dirc:
    mov ah, 0x0E
    mov al, '/'
    int 0x10
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ; Lists File and jump to the next
    mov si, 0x5200
    mov cx, 11 ; Filename Size
    mov dx, 64 ; Max Files in root dir
    push si
.D_Loopf:
    mov ah, 0x0E
    cmp byte [ds:si], 0x00
    mov cx, 11 ; Filename Size
    je .D_Skip
.D_Loop:
    lodsb
    int 0x10
    loop .D_Loop
    mov al, 0x20
    int 0x10
    add si, 2
    mov ax, word [ds:si]
    call print_dec
    mov si, .dldb
    int 0x62

    jmp .D_Skip
.dldb db " bytes", 0x00
.D_Skip:
    pop si
    add si, 16
    mov cx, 11
    dec dx
    cmp dx, 0x00
    je .done
    push si
    jmp .D_Loopf
.done:
    popa
    retf

;___________________________________________________________


read_file:
    ; Inputs:
    ;   AX = Starting Cluster
    ;   ES = Destination Cluster
    ; Outputs:
    ;   Loads file at ES:BX
    pusha

    ;_
    push ax
    mov ax, 0x0000
    mov ds, ax
    pop ax
    ;_

    mov di, 0x4000  ; DS:DI = FAT
    mov dx, 0x0000  ; Cluster offsetting | Max Loaded file size is 63 MiB~
.L_loop:
    push di

    mov bx, ax ; BX = Cluster number
    shl ax, 1  ; DI = FAT Next cluster, AX = FAT Index Value
    add di, ax ; ____| 
    mov ax, word [ds:di]

    ; Load Cluster
    ;_
    push ax
    push bx
    mov ax, bx
    add ax, 16 ; data area ALWAYS starts >= LBA 16
    mov bx, 0x0000
    add bx, dx
    int 0x60
    add dx, 512
    pop bx
    pop ax

    cmp dx, 63488
    jae .oversized
    cmp ax, 0xFFFF
    je .EoF
    cmp ax, 0x0000
    je .Empty_Error

    pop di
    jmp .L_loop

.oversized:
    pop di
    mov si, .oddb
    int 0x62
    popa
    retf
.oddb db "The File is way too large to load! (63.4 KB Max)", 0x00
.EoF:
    pop di
    xor bh, bh
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    popa
    retf
.Empty_Error:
    pop di
    mov si, .eedb
    int 0x62
    popa
    retf
.eedb db "Attempted to read a Reserved Cluster / Invalid Cluster!, file may be corrupted", 0x00

;___________________________________________________________

write_file:
    ; Inputs:
    ;   DS:SI = Filename
    ;   ES:DI = Data Buffer  
    ;   AX    = File size
    ; Outputs:
    ;   Just Writes the file
    pusha
    cmp ax, 0x0000
    je .size_error
    push ds
    push si
    push ax
    push es
    push di

    push ds
    push si
    call far 0x0000:0x2009
    cmp bl, 0xFF
    je .file_exists
    jmp .skip_search
.file_exists:
    xor dx, dx
    mov ds, dx
    mov si, .fledb
    int 0x62
    mov ah, 0x00
    int 0x16
    cmp ah, 0x15
    je .overwrite
    cmp ah, 0x31
    je .cancel
    jmp .file_exists
.fledb db "File already exists!, do you want to overwrite? (Y/N)", 0x00
.cancel:
    pop si
    pop ds

    pop di
    pop es
    pop ax
    pop si
    pop ds
    mov si, .canceldb
    xor dx, dx
    mov ds, dx
    int 0x62
    popa
    retf
.overwrite:
    pop si
    pop ds
    push ds
    push si
    call far 0x0000:0x200F
    jmp .skip_search
.canceldb db "Write Operation Aborted", 0x00    
.skip_search:
    pop si
    pop ds
    pop di
    pop es
    pop ax
    pop si
    pop ds
    cmp ax, 63488
    jae .size_error
    mov word [cs:.file_size], ax
    push ds
    push si
    push di
    mov bp, 0x4000; CS:BP = FAT Pointer
    ; Calculates how many LBAs needed to write
    ;_
    xor dx, dx
    mov bx, 512
    div bx
    cmp dx, 0x0000
    je .skip_ceil
    inc ax
.skip_ceil:
    mov dx, ax
    jmp .find_cluster
.size_error:
    mov si, .sdb
    int 0x62
    popa
    retf
.sdb db "File is way too large to write! (63.4 KB Max)", 0x00


.find_cluster:
    ; DX = Number of LBAs to write
    ; CS:BP = FAT Pointer
    ; CS:SI = Second FAT Pointer
    ; ES:DI = Data Segment
    ; AX    = Starting Cluster of the new file
    ; SI    = Current Data offset
    pop di
    mov si, 0x4000
    mov cx, 2296  ; Number of Clusters to search by
    call .finder
    mov ax, bp
    sub ax, 0x4000
    shr ax, 1
    mov word [cs:.start_cluster], ax

.find_cloop:
    mov bx, bp ; BX = Next Cluster
    sub bx, 0x4000                                      
    dec dx     ; DX = Remaining Clusters to write>______
;                                                       |
    ; Write Cluster data onto disk                      |
    ;_                                                  |
    mov ax, bx ;                                        |
    shr ax, 1  ;                                        |
    add ax, 16 ; Data area ALWAYS starts >= Cluster 16  |
    push bx ;                                           |
    mov bx, di ;                                        |
    push di;                                            |
    int 0x61 ;                                          |
    pop di  ;                                           |
    pop bx ;                                            |
    ;_                                                  |
;                                                       |
    cmp dx, 0 ;>________________________________________|
    je .write_dir_entry
    ; Update FAT
    ;_
    push bp
    add bp, 2
    mov cx, 2296
    mov bp, 0x0000
    call .finder
    mov ax, bp
    sub ax, 0x4000
    shr ax, 1
    
    pop bx
    mov word [cs:bx], ax
    ;_
    add di, 512
    jmp .find_cloop

; Finds Free Clusters, resulting in BP = free cluster position
;_
.finder:
    nop
.finder_loop:
    cmp word [cs:bp], 0x0000
    je .finder_done
    add bp, 2
    loop .finder_loop
.disk_error:
    xor ax, ax
    mov ds, ax
    mov si, .ddb
    int 0x62
    pop si
    pop ds
    pop ax
    popa
    retf
.finder_done:

    ret
.ddb db "Current Storage is full! cannot write file.", 0x00

.write_dir_entry:
    mov word [cs:bp], 0xFFFF ; Places EoF on FAT, not related to write directory entry routine.
.find_free_dir_entry:
    ; Pretty Self Explanatory.
    ;_
    mov cx, 64
    mov bp, 0x5200
.ffde_loop:
    cmp byte [cs:bp], 0x00
    je .ffde_make
.ffde_skip:
    jcxz .dir_space_error
    add bp, 16    
    loop .ffde_loop
    ;_
.dir_space_error:
    mov si, .dsedb
    xor ax, ax
    mov ds, ax
    int 0x62
    pop si
    pop ds
    popa
    retf
.ffde_make:
    ; Creates the Directory Entry.
    ;_
    mov ax, 0x0000
    mov es, ax
    mov di, bp
    pop si
    pop ds
    mov cx, 11
.copy_name_to_entry:
    lodsb
    stosb
    loop .copy_name_to_entry
    mov ax, [cs:.start_cluster]
    stosw
    mov ax, [cs:.file_size]
    stosw
    call update_FAT_and_ROOT
    popa
    retf
    ;_

.dsedb db "Directory does not have enough space!", 0x00
.file_size dw 0x0000
.start_cluster dw 0x0000







;___________________________________________________________




rem_file:
    ; Merges Search and Read Functions and repurposes them for deleting a file.
    ; Inputs:
    ;   DS:SI = Filename 
    ; Output:
    ;   Deletes the file
    jmp .search_file
.search_file:
    pusha
    call load_FAT_and_ROOT
    ; Input:
    ;       DS:SI = Filename (11 chars max)
    ; Output:
    ;       AX = File's Starting Cluster
    ;       BL = does it exists? (0xFF = Y | 0x00 = N)
    ;       CX = File Size

    ; Points to the Root directory.
    ;_
    push ax
    xor ax, ax
    mov es, ax
    mov di, 0x5200
    pop ax
    ;_
    cld
    mov cx, 11  ; 11 bytes for Filename
    mov dx, 64  ; 64 Root Entries Max
    push di
    push si
.search_loop:
    ; Loops onto the root directory entry until find a match
    ;_
    repe cmpsb
    jz .s_done
    ;_
.s_invalid:
    ; If Invalid, jumps to the next root dir entry or raises a fileNotFound error
    ;_
    pop si
    pop di
    dec dx
    cmp dx, 0
    je .fnferror
    mov cx, 11
    add di, 16
    push di
    push si
    jmp .search_loop
    ;_
.s_done:
    ; Read Docstring output details.
    ;_ 
    pop si
    pop di

    mov byte [es:di], 0x00
    add di, 11
    mov ax, word [es:di]
    mov word [cs:.sd_sc], ax ; Starting Cluster
    mov si, .sd_donestring
    int 0x62
    mov ax, word [cs:.sd_sc]

    jmp .read_file
    ;_
.sd_donestring db "Gotcha!", 0x00
.sd_sc dw 0x0000

.fnferror:
    ; Quits Search Operation due to file not found error.
    ;_
    mov si, .fnfstring
    int 0x62
    popa
    mov bl, 0x00
    retf
    ;_
.fnfstring db "err_fileNotFound", 0x00


.read_file:
    ; Inputs:
    ;   AX = Starting Cluster
    ;   ES = Destination Cluster
    ; Outputs:
    ;   Deletes the clusters.
    ;_
    push ax
    mov ax, 0x0000
    mov ds, ax
    pop ax
    ;_

    mov di, 0x4000  ; DS:DI = FAT
.L_loop:
    push di

    shl ax, 1  ; DI = FAT Next cluster, AX = FAT Index Value
    add di, ax ; ____| 
    mov ax, word [ds:di]
    mov word [ds:di], 0x0000

    cmp ax, 0xFFFF
    je .EoF
    cmp ax, 0x0000
    je .Empty_Error

    pop di
    jmp .L_loop

.EoF:
    pop di
    xor bh, bh
    mov ah, 0x0E
    mov al, '#'
    int 0x10
    call update_FAT_and_ROOT
    popa
    retf
.Empty_Error:
    pop di
    mov si, .eedb
    int 0x62
    popa
    retf
.eedb db "Attempted to delete a Reserved Cluster / Invalid Cluster!, file may be corrupted", 0x00

;___________________________________________________________
; Extra Essentials for in-code only
print_dec:
    ; Input:  AX
    ; Output:
    ;       prints decimal value in screen
    push ax
    push bx
    push cx
    push dx

    mov cx, 0        
    mov bx, 10       

    or ax, ax       
    jnz .dloop
    mov al, '0'
    mov ah, 0x0E
    mov bh, 0x00
    push cx
    int 0x10
    pop cx
    jmp .pdone

.dloop:
    xor dx, dx
    div bx    
    push dx       
    inc cx
    or ax, ax
    jnz .dloop    

.dprint:
    pop dx              
    add dl, '0'       
    mov ah, 0x0E
    mov al, dl
    mov bh, 0x00
    int 0x10
    loop .dprint

.pdone:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
