# Autonomous batch repeater: physical verification

Tool: 2018.1. Device: xc7z010clg400-1. Clock: 100 MHz.

One programming operation; both modes use the same bitstream.

Bitstream SHA256: `0b81ab14ead59e850ae6cb082d24a057077427ca4bf2bff80b22fc3663a9cece`

Probe file SHA256: `9b6e5ddc57ef04ec2be577c083a6a17d766afa6bc8af481235514ffd461be82a`

| Mode | Weight | Batches | Products | Reads | Loads | Cycles | Checksum | Last product |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A | 7 | 1 | 4 | 4 | 4 | 14 | 28 | 28 |
| B | 7 | 1 | 4 | 1 | 1 | 14 | 28 | 28 |
| A | 9 | 4 | 16 | 16 | 16 | 56 | 144 | 36 |
| B | 9 | 4 | 16 | 4 | 4 | 56 | 144 | 36 |
| A | -2 | 16 | 64 | 64 | 64 | 224 | -128 | -8 |
| B | -2 | 16 | 64 | 16 | 16 | 224 | -128 | -8 |
| A | 7 | 10000000 | 40000000 | 40000000 | 40000000 | 140000000 | 280000000 | 28 |
| B | 7 | 10000000 | 40000000 | 10000000 | 10000000 | 140000000 | 280000000 | 28 |
| B | 7 | 10000000 | 40000000 | 10000000 | 10000000 | 140000000 | 280000000 | 28 |
| A | 7 | 10000000 | 40000000 | 40000000 | 40000000 | 140000000 | 280000000 | 28 |

All counter, checksum, last-product and completion assertions passed.
The checksum is a functional aggregate check, not a proof of every output sample.
ILA acquisition was not armed. JTAG supplies configuration/start and reads completion.
The hardware window is cycles / 100000000 seconds, not the host wait duration.

Measured voltage/current and electrical energy: **not measured**.
