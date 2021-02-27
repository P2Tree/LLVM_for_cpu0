define zeroext i1 @verify_load_bool() {
entry:
  %retval = alloca i1, align 1
  store i1 1, i1* %retval, align 1
  %0 = load i1, i1* %retval
  ret i1 %0
}
