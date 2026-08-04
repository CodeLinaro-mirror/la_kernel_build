#include "mylib.h"
#include <linux/kernel.h>
#include <linux/module.h>

void mylib_function(void) {
    pr_info("Hello from mylib\n");
}
EXPORT_SYMBOL_GPL(mylib_function);
