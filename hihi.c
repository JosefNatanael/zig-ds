#include <stdint.h>

inline int hello(const int* ctrl) {
    return ((uintptr_t)ctrl) >> 12;

}

int main(void) {
}
