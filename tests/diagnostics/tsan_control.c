#include <pthread.h>
#include <stdio.h>
static int value;
static void *worker(void *unused) {
  (void)unused;
  value++;
  return 0;
}
int main(void) {
  pthread_t a,b;
  pthread_create(&a,0,worker,0);
  pthread_create(&b,0,worker,0);
  pthread_join(a,0); pthread_join(b,0);
  puts("C runtime reached main");
  return 0;
}
