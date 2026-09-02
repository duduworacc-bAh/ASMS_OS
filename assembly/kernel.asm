[BITS 16]
[ORG 0x0000]
[CPU 286]

mov ax, 0x2000
mov ss, ax
mov sp, 0xFFFF

mov ax, 0x1000
mov ds, ax
mov es, ax

mov ah, 0x00
mov al, 0x02
int 0x10
mov si, testmsg
int 0x62
mov si, testmsg1
int 0x62
jmp code
testmsg db "Welcome to ASMS-OS!, made with ", 0x03, 0x00
testmsg1 db "By Dudedev and with support from KiddieOS.Community!", 0x00

;_____________________________________
;_____________________________________
code:
    mov si, 0x0000
    mov di, 0x0000
    nop
; Actual Code stuff goes here
call get_oem
jmp PROMPT


PROMPT:
    mov ax, 0x1000
    mov es, ax
    cld
    push di
    mov al, 0x00
    mov cx, 256
    mov di, 0xE000
    rep stosb
    pop di

    mov si, 0xD000
    mov cx, 16
    mov ah, 0x0E
    .rdloop:
        lodsb
        cmp al, 0x20
        je .rdskip
        cmp al, 0x00
        je .rdskip
        int 0x10
        loop .rdloop
        jmp .rddone

    .rdskip:
        loop .rdloop
    .rddone:
        mov bh, 0x00
        nop
        mov al, '>'
        int 0x10
        mov al, ' '
        int 0x10
    call .get_bufferb  ; 256 bytes long keyboard buffer for command input at 0x1E000 | 0x1000:0xE000
    call .tokenize     ; processed commands end up in: CMD Token -> 0x1E100, ARG1 -> 0x1E200, ARG2 -> 0x1E300
    
    mov ax, 0x1000
    mov es, ax

    mov di, 0xE100
    call upper   

    mov di, 0xE200
    call upper   

    mov di, 0xE300
    call upper   

    call .internal 
    jmp PROMPT
;_____________________________________
; PROMPT Data
.nocmderr db "No Command or Filename provided!", 0x00
;_____________________________________
; PROMPT Functions
.get_bufferb:
    mov ax, 0x1000
    mov es, ax
    mov si, 0xE000
.get_buffer:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je .bgdone
    cmp al, 0x08
    je .bgbackspace
    cmp si, 0xE100
    jge .bgskip
    mov ah, 0x0E
    mov bh, 0x00 
    int 0x10
    mov byte [ES:SI], al
    inc si
    jmp .get_buffer

.bgbackspace:
    cmp si, 0xE000
    jle .bgdeny
    mov byte [ES:SI-1], 0x00
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    dec si
    jmp .get_buffer
.bgdeny:
    mov si, 0xE000
    jmp .get_buffer

.bgskip:
    mov si, 0xE100
    jmp .get_buffer
.bgdone:
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

.tokenize:
    push ds
    push es
    mov si, 0xE000
    mov ax, 0x1000
    mov ds, ax
    mov es, ax

    push di
    mov al, 0x00
    mov di, 0xE100
    mov cx, (0xE200 - 0xE100) + (0xE300 - 0xE200) + 256 
    rep stosb
    pop di

    pop es
    pop ds

    mov bp, 0xE100 ; CMD   [ES:BP]_ Command token
    mov di, 0xE200 ; ARG 1 [ES:DI]-Both or ARG 2 can be empty
    mov bx, 0xE300 ; ARG 2 [ES:BX]_|

    cmp byte [es:si], 0x00
    je .tknocmd

.tkloop1:
    cmp byte [es:si], 0x20
    je .tkargloop1_pre
    cmp byte [es:si], 0x00
    je .tkdone

    mov al, byte [es:si]
    mov byte [es:bp], al
    inc si
    inc bp
    jmp .tkloop1
.tkdone:
    mov byte [es:bp], 0x00
    ret
.tk1done:
    mov byte [es:di], 0x00
    ret
.tk2done:
    mov byte [es:bx], 0x00
    ret

.tkargloop1_pre:
    inc si
.tkargloop1:
    cmp byte [es:si], 0x20
    je .tkargloop2_pre
    cmp byte [es:si], 0x00
    je .tk1done

    mov al, byte [es:si]
    mov byte [es:di], al
    inc si
    inc di
    jmp .tkargloop1
.tkargloop2_pre:
    inc si
.tkargloop2:
    cmp byte [es:si], 0x00
    je .tk2done

    mov al, byte [es:si]
    mov byte [es:bx], al
    inc si
    inc bx
    jmp .tkargloop2
.tknocmd:
    push cs
    pop ds
    mov si, .nocmderr
    int 0x62
    mov ax, 0x1000
    mov ds, ax
    ret

.internal:
    mov ax, 0x1000 ;_
    mov es, ax     ;Check Command Token
    mov si, 0xE100 ;_|
    mov di, .i_cmdtable

.itloop:
    mov bp, word [es:di]
    cmp bp, 0xFFFF
    je .itbadcmd
    push di
    push si
.itcheck:
    mov al, [es:bp]
    mov ah, [es:si]
    cmp al, ah
    jne .continue
    or al, al
    jz .done
    inc si
    inc bp
    jmp .itcheck
.continue:
    pop si
    pop di

    add di, 4 
    jmp .itloop
.done:
    pop si
    pop di
    add di, 2
    call [es:di]
    ret
.i_cmdtable:
    .iDIR dw .dir_name, .dir_handler
    .iVER dw .ver_name, .ver_handler
    .iREB dw .reb_name, .reb_handler
    .iTES dw .tes_name, .tes_handler
    .iREM dw .rem_name, .rem_handler
    .iCHE dw .che_name, .che_handler
    .iRUN dw .run_name, .run_handler
    .iTYP dw .typ_name, .typ_handler
    dw 0xFFFF, 0xFFFF ; End of cmdtable
.dir_name db "DIR", 0
.ver_name db "VER", 0
.reb_name db "REBZOO", 0
.tes_name db "WRITE", 0
.rem_name db "DEL", 0
.che_name db "CHECK", 0
.run_name db "RUN", 0
.typ_name db "TYPE", 0

.dir_handler:
    call far 0x0000:0x200C
    mov ax, 0x1000
    mov ds, ax
    ret
.ver_handler:
    mov ax, 0x1000
    mov ds, ax
    mov si, .verhn
    int 0x62
    mov si, .verhm
    int 0x62
    mov si, .verho
    int 0x62
    mov si, kernel_ver
    int 0x62
    ret
.verhn db "Aurora Software Management System", 0x00
.verhm db "__________________________________", 0x00
.verho db "Kernel Version:", 0x00

.reb_handler:
    mov ax, 0x0040
    mov es, ax
    mov ax, 0x1234
    mov di, 0x0072
    stosw
    jmp 0xFFFF:0x0000


.tes_handler:
    mov ax, 0x1000
    mov es, ax
    mov di, 0xE200
    mov si, 0XE200
    call file_convert

    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    xor bl, bl
    call far 0x0000:0x2009
    cmp bl, 0xFF
    je .tesferr

    
    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    mov ax, 0x1E30
    mov es, ax
    mov ax, 256   ; Standard Size for buffer is 256 bytes, so here we assume the file will be 256 bytes long
    call far 0x0000:0x2006
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    ret
.tesferr:
    mov ax, 0x1000
    mov ds, ax
    mov si, .tesferrdb
    int 0x62
    ret
.tesferrdb db "Error: File Already Exists!", 0x00
.rem_handler:
    mov ax, 0x1000
    mov es, ax
    mov di, 0xE200
    mov si, 0XE200
    call file_convert
    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    call far 0x0000:0x200F
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    ret
.che_handler:
    mov ax, 0x1000
    mov es, ax
    mov di, 0xE200
    mov si, 0XE200
    call file_convert
    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    call far 0x0000:0x2009
    cmp bl, 0xFF
    jne .cheferr
    mov ax, cx
    call print_dec

    mov ax, 0x1000
    mov es, ax
    mov ds, ax
    mov si, .chedb
    mov ah, 0x0E
    int 0x62

    ret

.cheferr:
    mov ax, 0x1000
    mov ds, ax
    mov si, .cheferrdb
    int 0x62
    ret
.cheferrdb db "Error: File Not Found!", 0x00
.chedb db " bytes", 0

.run_handler:
    mov ax, 0x1000
    mov es, ax
    mov di, 0xE200
    mov si, 0XE200
    call file_convert
    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    call far 0x0000:0x2009
    cmp bl, 0xFF
    jne .runferr
    push ax
    mov ax, 0x3000
    mov es, ax
    pop ax
    call far 0x0000:0x2003
    call far 0x3000:0x0000 ; Run loaded file
    mov ax, 0x1000
    mov es, ax
    mov ds, ax
    ret
.runferr:
    mov ax, 0x1000
    mov ds, ax
    mov si, .runferrdb
    int 0x62
    ret
.runferrdb db "Error: File Not Found!", 0x00

.typ_handler:
    mov ax, 0x1000
    mov es, ax
    mov di, 0xE200
    mov si, 0XE200
    call file_convert
    mov ax, 0x1000
    mov ds, ax
    mov si, 0xE200
    call far 0x0000:0x2009
    push cx
    push ax

    cmp bl, 0xFF
    jne .typferr
    jcxz .typfnull
    mov ax, 0x3000
    mov es, ax
    mov ds, ax

    pop ax

    call far 0x0000:0x2003
    mov ax, 0x3000
    mov es, ax
    mov ds, ax
    pop cx

    mov ah, 0x0E
    mov si, 0x0000
.typloop:
    lodsb
    int 0x10
    loop .typloop

    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10

    mov ax, 0x1000
    mov es, ax
    mov ds, ax
    ret

.typferr:
    pop ax
    pop cx
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov si, .typferrdb
    int 0x62
    ret
.typfnull:
    pop ax
    pop cx
    mov ax, 0x1000
    mov ds, ax
    mov es, ax
    mov si, .typfnulldb
    int 0x62
    ret
.typfnulldb db "Error: File is Empty!", 0x00
.typferrdb db "Error: File Not Found!", 0x00

.itbadcmd:
    mov si, .itbadcmderr
    int 0x62
    ret
.itbadcmderr db "Invalid Command or Filename.", 0x00
;_____________________________________
;_____________________________________
; Functions
get_oem:
    ; Output:
    ;       0x1000:0xD000 | 0x1D000 =  OEM Name
    pusha
    mov cx, 16 ; OEM Size
    xor ax, ax      ;-ES:DI = OEM is always at the 32 bytes metadata on 0x07C02 [0x0000:0x7C02]
    mov es, ax      ; |
    mov di, 0x7C02  ;_|

    mov ax, 0x1000  ;-DS:SI = OEM Destination
    mov ds, ax      ; |
    mov si, 0xD000  ;_|
.loop:
    mov al, [ES:DI]
    mov [DS:SI], al
    inc si
    inc di
    loop .loop
    popa
    ret

upper:
    ; Input: ES:DI = Buffer Pointer
    ; Output: Expected Upper() function
    push ax
    push di
.uloop:
    mov al, [es:di]
    cmp al, 0x00
    je .udone
    cmp al, 'a'
    jb .uskip
    cmp al, 'z'
    ja .uskip
    sub al, 0x20
    mov [es:di], al
.uskip:
    inc di
    jmp .uloop
.udone:
    pop di
    pop ax
    ret

file_convert:
    ; Converts the target string into 8:3 FAT Format
    ; 
    ; Input:
    ;   ES:SI = Buffer
    ; Output:
    ;   ES:DI = Output Buffer
    
    mov cx, 256 ; buffer size
    mov dx, di
.nloop:
    mov al, byte [es:si]
    cmp al, '.'
    je .continue
    mov byte [es:di], al
    inc si
    inc di
    loop .nloop  ; |
                 ;_|
.overr:
    mov ax, 0x1000
    mov ds, ax
    mov si, .overrdb
    int 0x62
    ret
.continue:
    inc si
    mov bp, di


    push si
    mov di, dx
    add di, 8
    mov cx, 3
.lastloop:
    mov al, byte [es:si]
    mov byte [es:di], al
    inc si
    inc di
    loop .lastloop
    pop si

    mov di, bp
    mov cx, dx
    add cx, 8
    cmp di, cx
    jae .skip_pad
.pad_loop:
    mov byte [es:di], ' '
    inc di
    cmp di, cx
    jb .pad_loop
.skip_pad:
    ret

.overrdb db "Filename is way too large or extension not specified!", 0x00


    
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
    int 0x10
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


kernel_ver db "1.0", 0x00
