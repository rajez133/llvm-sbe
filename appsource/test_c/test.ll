; ModuleID = 'test.c'
source_filename = "test.c"
target datalayout = "E-m:e-p:32:32-Fn32-i64:64-n32"
target triple = "powerpc-unknown-linux-gnu"

; Function Attrs: noinline nounwind optnone uwtable
define dso_local i32 @main() #0 {
  %1 = alloca i32, align 4
  %2 = alloca ptr, align 4
  %3 = alloca i64, align 8
  store i32 0, ptr %1, align 4
  store ptr inttoptr (i32 327680 to ptr), ptr %2, align 4
  %4 = load ptr, ptr %2, align 4
  %5 = load volatile i64, ptr %4, align 8
  store volatile i64 %5, ptr %3, align 8
  %6 = load volatile i64, ptr %3, align 8
  %7 = or i64 %6, -9223372036854775808
  store volatile i64 %7, ptr %3, align 8
  %8 = load volatile i64, ptr %3, align 8
  %9 = load ptr, ptr %2, align 4
  store volatile i64 %8, ptr %9, align 8
  br label %10

10:                                               ; preds = %0, %10
  br label %10
}

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="ppc" "target-features"="+hard-float" }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"PIE Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 2}
!4 = !{i32 7, !"frame-pointer", i32 2}
!5 = !{!"clang version 21.1.4 (/root/llvm-project/llvm/llvm 05b4df7ad6fdff0f029951a5b3fe2b3fa4cd20e9)"}
