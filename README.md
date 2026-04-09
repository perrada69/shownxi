# SHOWNXI — NXI Viewer Dot Command for ZX Spectrum Next

**Credit: Shrek/MB Maniax 2026**

## Popis

Dot command pro NextZXOS, který zobrazí obrázek ve formátu NXI (256x192, Layer 2 256-colour mode).

## Podporované velikosti souboru

| Velikost | Obsah |
|----------|-------|
| 49 152 B | Jen obrazová data (256×192 px) |
| 49 664 B | Obrazová data + 512 B paleta (9-bit RRRGGGBBB × 256) |

## Použití

```
.shownxi nazev.nxi
.shownxi "nazev souboru.nxi"
.shownxi -h
```

## Sestavení (build)

```
sjasmplus --raw=shownxi shownxi.asm
```

Výstupní soubor `shownxi` zkopíruj do složky `/dot/` na SD kartě Nextu.

## Jak to funguje

1. Otevře soubor přes esxDOS F_OPEN
2. Aktivuje Layer 2 write mode (NextReg $12 = %00000011)
3. Mapuje 16K banky 8, 9, 10 (stránky 16–21) postupně do slotu $4000–$7FFF přes MMU registry $52/$53
4. Do každého banku načte 16 384 bytů přes F_READ
5. Pokusí se načíst dalších 512 bytů — pokud uspěje, nahraje paletu do Layer 2 palette přes NextReg $40/$44/$41
6. Vypne Layer 2 write enable, zobrazí Layer 2 (NextReg $12 = %00000001)

## Formát palety v NXI (512 bytů)

Pro každý ze 256 barev 2 byty:
- byte 0: bity 8..1 9-bitové barvy (RRRGGGBB)
- byte 1: bit 0 = LSB barvy (B)

## Poznámky

- Soubor nesmí mít NXI header (čistá data od offsetu 0)
- Layer 2 zůstane zobrazená i po skončení dot commandu
- Výchozí paleta (pokud není v souboru) zůstane beze změny
