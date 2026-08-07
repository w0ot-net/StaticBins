volatile unsigned int static_bins_probe_value = 0x12345678U;

int
main(void)
{
    return static_bins_probe_value == 0x12345678U ? 0 : 1;
}
