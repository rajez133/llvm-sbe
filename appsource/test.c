// PPE Load Virtual Double operation
#define PPE_LVD(_m_address, _m_data) \
    asm volatile \
    ( \
      "lvd %[data], 0(%[address]) \n" \
      :  [data]"=d"(_m_data) \
      :  [address]"b"(_m_address) \
    );

// PPE Store Virtual Double operation
#define PPE_STVD(_m_address, _m_data) \
    asm volatile \
    ( \
      "stvd %[data], 0(%[address]) \n" \
      : [data]"=&d"(_m_data) \
      : "[data]"(_m_data), \
      [address]"b"(_m_address) \
      : "memory" \
    );

int main(void) {
  volatile int a = 20;
  volatile int b = 20;
  volatile int c = a + b;

  // Update ready bit in MSG REG (64-bit)
  unsigned int MSG_REG_ADDR = 0x50009;
  volatile unsigned long long val;
  PPE_LVD(MSG_REG_ADDR, val);

  val |= (1ULL << 63); // set bit 63

  PPE_STVD(MSG_REG_ADDR, val); // store 64-bit value

  // infinite loop
  while (1)
    ;
  return c;
}
