; Autor reseni: Boris Semanco - xseman06
; Pocet cyklu k serazeni puvodniho retezce: 2681
; Pocet cyklu razeni sestupne serazeneho retezce: 2710
; Pocet cyklu razeni vzestupne serazeneho retezce: 2625
; Pocet cyklu razeni retezce s vasim loginem: 610
; Implementovany radici algoritmus: Bubble Sort
; ------------------------------------------------

; DATA SEGMENT
                .data
; login:          .asciiz "vitejte-v-inp-2023"    ; puvodni uvitaci retezec
; login:          .asciiz "vvttpnjiiee3220---"  ; sestupne serazeny retezec
; login:          .asciiz "---0223eeiijnpttvv"  ; vzestupne serazeny retezec
login:          .asciiz "xseman06"            ; SEM DOPLNTE VLASTNI LOGIN
                                                ; A POUZE S TIMTO ODEVZDEJTE

params_sys5:    .space  8   ; misto pro ulozeni adresy pocatku
                            ; retezce pro vypis pomoci syscall 5
                            ; (viz nize - "funkce" print_string)

; CODE SEGMENT
                .text

main:
    daddi r4, r0, login
    daddi r2, r0, 0         ; n = 0
    
    jal arr_size            ; get arr size and sort it

    daddi r4, r0, login     ; reset arr pointer
    jal print_string        ; print sorted arr

    syscall 0

arr_size:
    lbu r5, 0(r4)           ; arr[i]
    beqz r5, bubble_sort    ; if arr[i] == '\0' then start bubble sort
    daddi r2, r2, 1         ; n++
    daddi r4, r4, 1         ; moves arr pointer to next char
    j arr_size              ; loop

bubble_sort:
    daddi r4, r0, login     ; reset arr pointer
    daddi r1, r0, 0         ; i = 0

outer_loop:
    daddi r6, r2, -1        ; n - 1, r6 = n - 1
    beq r1, r6, done_sorting ; if i == n - 1, sorting complete

    dsubu r8, r6, r1        ; r8 = n - 1 - i

    daddi r3, r0, 0         ; j = 0
    inner_loop:

        beq r3, r8, outer_done ; if j == n - i - 1, move to outer loop

        lbu r10, 0(r4)      ; arr[j]
        lbu r11, 1(r4)      ; arr[j + 1]

        slt r12, r10, r11   ; arr[j] < arr[j + 1], r12 = 1 if true
        bnez r12, inner_done ; if arr[j] >= arr[j + 1] then inner_done

        sb r11, 0(r4)       ; arr[j] = arr[j + 1]
        sb r10, 1(r4)       ; arr[j + 1] = arr[j]
 
    inner_done:
        daddi r3, r3, 1     ; j++
        daddi r4, r4, 1     ; moves arr pointer to next char
        j inner_loop        ; loop

outer_done:
    daddi r1, r1, 1         ; i++
    daddi r4, r0, login     ; reset arr pointer
    j outer_loop            ; loop

done_sorting:
    jr r31                  ; return from main




print_string:   ; adresa retezce se ocekava v r4
                sw      r4, params_sys5(r0)
                daddi   r14, r0, params_sys5    ; adr pro syscall 5 musi do r14
                syscall 5   ; systemova procedura - vypis retezce na terminal
                jr      r31 ; return - r31 je urcen na return address
