#include "klessydra_defs.h"

#define MHARTID_IDCORE_MASK 15
#define THREAD_POOL_SIZE 4

#define spmaddrA 0x00200000
#define spmaddrB 0x00200200
#define spmaddrC 0x00200400
#define spmaddrD 0x00200600

#ifndef __KLESSYDRACFUNCTIONS_H__
#define __KLESSYDRACFUNCTIONS_H__

void CSR_MVSIZE(int rs1);

int kaddv8(void* rd, void* rs1, void* rs2);
int kaddv16(void* rd, void* rs1, void* rs2);
int kaddv32(void* rd, void* rs1, void* rs2);

int kaddv8_v2(void* rd, void* rs1, void* rs2, int size);
int kaddv16_v2(void* rd, void* rs1, void* rs2, int size);
int kaddv32_v2(void* rd, void* rs1, void* rs2, int size);

int kdotp8(void* rd, void* rs1, void* rs2);
int kdotp16(void* rd, void* rs1, void* rs2);
int kdotp32(void* rd, void* rs1, void* rs2);

int kdotp8_v2(void* rd, void* rs1, void* rs2, int size);
int kdotp16_v2(void* rd, void* rs1, void* rs2, int size);
int kdotp32_v2(void* rd, void* rs1, void* rs2, int size);

int ksvmul8(void* rd, void* rs1, void* rs2);
int ksvmul16(void* rd, void* rs1, void* rs2);
int ksvmul32(void* rd, void* rs1, void* rs2);

int ksvmul8_v2(void* rd, void* rs1, void* rs2, int size);
int ksvmul16_v2(void* rd, void* rs1, void* rs2, int size);
int ksvmul32_v2(void* rd, void* rs1, void* rs2, int size);

int* kless_dot_product_8(void* result, void* src1, void* src2, int size);
int* kless_dot_product_16(void* result, void* src1, void* src2, int size);
int* kless_dot_product_32(void* result, void* src1, void* src2, int size);

unsigned char*  kless_vector_addition_8(void* result, void* src1, void* src2, int size);
unsigned short* kless_vector_addition_16(void* result, void* src1, void* src2, int size);
unsigned int*   kless_vector_addition_32(void* result, void* src1, void* src2, int size);

int* kless_scalar_vect_mult_8(void* result, void* src1, void* src2, int size);
int* kless_scalar_vect_mult_16(void* result, void* src1, void* src2, int size);
int* kless_scalar_vect_mult_32(void* result, void* src1, void* src2, int size);

int kmemld(void* rd, void* rs1, int rs2);

int kmemstr(void* rd, void* rs1, int rs2);

#endif