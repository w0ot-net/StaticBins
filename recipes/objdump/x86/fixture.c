extern int static_bins_missing(int);

int static_bins_data = 47;

static int
static_bins_local(int value)
{
    return value + static_bins_data;
}

int
static_bins_probe(int value)
{
    return static_bins_missing(static_bins_local(value));
}

int
main(void)
{
    return static_bins_local(0) == 47 ? 0 : 1;
}
