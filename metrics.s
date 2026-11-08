.intel_syntax noprefix
.text
.globl _metrics
_metrics:
 push ebp
 mov ebp, esp
 push dword ptr [ebp + 12]
 push dword ptr [ebp + 8]
 call dword ptr [0x53b024]
 test eax, eax
 jz done
 sub esp, 8
 lea ecx, [ebp - 8]
 push ecx
 push 2
 push 0x53a460
 push dword ptr [ebp + 8]
 call dword ptr [0x53b038]
 test eax, eax
 jz success
 mov ecx, [ebp - 8]
 test ecx, ecx
 jle success
 mov edx, [ebp + 12]
 mov dword ptr [edx + 24], ecx
success:
 mov eax, 1
done:
 mov esp, ebp
 pop ebp
 ret 8
 .org 0x50, 0x90
 .byte 0x93, 0xfa
