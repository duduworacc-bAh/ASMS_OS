[BITS 16]
[ORG 0x7C00]
[CPU 286]
jmp code
; Disk Metadata (32 Bytes | starts at offset 0x02 / LBA 0 )
; Code starts at offset 0x22 / LBA 0 )
OEM_NAME db "AURORABOOT      "
LAST_DR  db 0x00            ; LAST_DR is a tempvar
times 15 db 0x00
;_________________________________________
; Code
code:
    nop
    xor ax, ax
    mov es, ax
    mov ds, ax
    mov ax, 0x5000
    mov ss, ax
    mov sp, 0xFFFF

mov [LAST_DR], dl

cli
CVT:
    mov si, 0x0180
    mov word [si], LBA_R
    mov si, 0x0182
    mov word [si], 0x0000

    mov si, 0x0184
    mov word [si], LBA_W
    mov si, 0x0186
    mov word [si], 0x0000

    mov si, 0x0188
    mov word [si], PRINT
    mov si, 0x018A
    mov word [si], 0x0000
sti
mov si, data0
int 0x62

xor ax, ax
mov es, ax
mov bx, 0x2000
mov ax, 1
int 0x60
mov bx, 0x2200
mov ax, 2
int 0x60
mov ax, 3
mov bx, 0x2400
int 0x60

jmp 0x0000:0x2000

data0 db "Booting ASMS...", 0

;_________________________________________
; Functions
LBA_R:
    ; Read LBA sector, works only with floppy disks 1.44MB
    ; inputs:
    ;   AX = 16 bit Sector
    ;   ES:BX = Target Address 
    pusha
    push es
    push bx

    mov bx, 18 ; SPT
    mov cx, 2  ; HPC
    

    push bx
    push ax  
    mov ax, cx
    mul bx
    mov bx, ax
    pop ax
    xor dx, dx
    div bx ; SI = C
           ; DI = R

    mov si, ax
    mov di, dx
    pop bx
    xor dx, dx
    mov ax, di
    div bx
    mov cx, ax
           ; CX = H
    mov ax, di
    xor dx, dx
    div bx
    inc dx
    mov ax, dx ; AX = S
    xor dx, dx


    pop bx
    pop es
    mov dh, cl  ; Head
    mov cl, al  ; Sector
    mov ah, 0x02
    mov al, 1

    push dx
    mov dx, si
    mov ch, dl  ; Cylinder
    pop dx

    push ds
    push ax
    
    xor ax, ax
    mov ds, ax

    mov dl, byte [LAST_DR]

    pop ax
    pop ds

    int 0x13
    jc .err
    popa
    iret
.err:
    mov si, .data0
    int 0x62
    jmp $
.data0 db "Internal Disk Error Occurred [CF = 1], system halted.", 0


LBA_W:
    ; Write LBA sector, works only with floppy disks 1.44MB or alike density HDs.
    ; inputs:
    ;   AX = 16 bit Sector
    ;   ES:BX = Target Address 
    pusha
    push es
    push bx

    mov bx, 18 ; SPT
    mov cx, 2  ; HPC
    

    push bx
    push ax  
    mov ax, cx
    mul bx
    mov bx, ax
    pop ax
    xor dx, dx
    div bx ; SI = C
           ; DI = R

    mov si, ax
    mov di, dx
    pop bx
    xor dx, dx
    mov ax, di
    div bx
    mov cx, ax
           ; CX = H
    mov ax, di
    xor dx, dx
    div bx
    inc dx
    mov ax, dx ; AX = S
    xor dx, dx


    pop bx
    pop es
    mov dh, cl  ; Head
    mov cl, al  ; Sector
    mov ah, 0x03
    mov al, 1

    push dx
    mov dx, si
    mov ch, dl  ; Cylinder
    pop dx

    push ds
    push ax
    
    xor ax, ax
    mov ds, ax

    mov dl, byte [LAST_DR]

    pop ax
    pop ds

    int 0x13
    jc .err
    popa
    iret
.err:
    mov si, .data0
    int 0x62
    jmp $
.data0 db "Internal Disk Error Occurred [CF = 1], system halted.", 0

PRINT:
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0x00
    je .ret
    int 0x10
    jmp .loop
.ret:
    mov al, 0x0A
    int 0x10
    mov al, 0x0D
    int 0x10
    iret

;_________________________________________
times 510 - ($ - $$) db 0
dw 0xAA55