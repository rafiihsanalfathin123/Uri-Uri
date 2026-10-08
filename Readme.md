# Uri-Uri : Optimasi Memori ExpandA ML-DSA-44

Proyek PERURI Hackathon 2026 yang mengembangkan subsistem **ExpandA pada ML-DSA-44** (*Module-Lattice-Based Digital Signature Algorithm*). Fokusnya adalah mengurangi kebutuhan penyimpanan matriks publik A sebagai bagian dari pengembangan hardware tanda tangan digital pascakuantum untuk perangkat identitas dengan sumber daya yang terbatas.

## Rancangan

Dari seed publik 256 bit, satu core **SHAKE128** membangkitkan data untuk rejection sampler. Sampler menghasilkan 256 koefisien per polinomial, kemudian packer mengemas setiap koefisien 23 bit ke dalam word 128 bit. Matriks A terdiri dari 4 × 4 polinomial.

Tersedia keluaran streaming serta pilihan buffer satu baris atau matriks penuh. Buffer satu baris dipertahankan sampai blok lain selesai menggunakannya, lalu dipakai kembali untuk baris berikutnya.

| Konfigurasi buffer | Kapasitas penyimpanan keluaran A |
| --- | ---: |
| Satu baris: 4 polinomial | 2.944 byte |
| Matriks penuh: 16 polinomial | 11.776 byte |

Penggunaan satu baris mengurangi **kapasitas penyimpanan keluaran A sebesar 75%** dibanding matriks penuh dengan format 23 bit yang sama. Angka ini tidak mewakili penghematan total memori ML-DSA.

## Isi repository

| Folder | Isi |
| --- | --- |
| [rtl/](rtl/) | Modul Verilog SHAKE128, sampler, packer, controller, dan buffer. |
| [tb/](tb/) | Testbench subsistem dan blok pendukung. |
| [scripts/](scripts/) | Generator data referensi, pengujian, analisis, dan persiapan Quartus. |
| [vectors/](vectors/) | Data uji dan keluaran referensi. |
| [results/](results/) | Log simulasi, perbandingan keluaran, dan ringkasan evaluasi. |

Top-level utama adalah [expanda_top.v](rtl/expanda_top.v) untuk streaming dan [expanda_buffered_top.v](rtl/expanda_buffered_top.v) untuk buffer. Konfigurasi buffer yang diuji: `ROWS=1` dan `ROWS=4`. Core SHAKE mendukung konfigurasi yang diuji `PARALLEL_LANES=1` dan `5`.

## Pengujian

Gunakan Python 3 dan Icarus Verilog (`iverilog`, `vvp`) pada PATH. Jalankan dari root repository melalui PowerShell:

```powershell
powershell -File scripts/test_v2.ps1
powershell -File scripts/test_v2_buffers.ps1
py -3 scripts/analyze_v2.py
```

Model acuan menggunakan `hashlib.shake_128`. Simulasi produsen memeriksa **16.384 koefisien pada setiap konfigurasi SHAKE**, termasuk pengujian stall dan reset. Pengujian tambahan memeriksa sampler, packing, serta pembacaan dan penggunaan ulang buffer. Rincian tersedia pada [hasil analisis V2](results/v2_analysis.json).

Perintah tersebut menulis ulang vector dan hasil pengujian. Gunakan V2 di atas untuk pengujian utama (desain lama tidak disertakan di repositori).

## Status dan dokumentasi

Cakupan saat ini adalah pembangkitan ExpandA dan pengelolaan keluarannya. Integrasi perkalian matriks-vektor, signing lengkap, serta demonstrasi DE10-Nano merupakan tahap lanjutan. Ringkasan evaluasi Quartus tersedia di `results/`; laporan mentah Fitter/Timing V2 belum disertakan.

Penjelasan blok, antarmuka, metode pembandingan, dan dokumen pendukung tersedia di **Google Drive tim**.

## Referensi

- [NIST FIPS 204 — ML-DSA](https://csrc.nist.gov/pubs/fips/204/final)
- [NIST FIPS 202 — SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [ML-DSA-OSH — baseline hardware](https://github.com/KULeuven-COSIC/ML-DSA-OSH)
