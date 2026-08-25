// hello-lyra — verifica di boot per Luckfox Lyra Plus (Rockchip RK3506G2).
//
// Non fa nulla di utile di per se': serve a rispondere alla domanda "il
// porting da SDK Luckfox a Buildroot upstream ha prodotto un sistema che
// gira davvero?". Per farlo legge quattro cose che, messe insieme, coprono
// i punti dove un porting fallisce in silenzio:
//
//   /proc/device-tree/model  il DTB caricato e' quello giusto?
//   /proc/uptime             il kernel e' arrivato allo userspace?
//   /proc/meminfo            il blob DDR ha inizializzato la RAM come previsto?
//   /proc/mtd                le partizioni da mtdparts= combaciano con
//                            parameter.txt?
//
// Cross-compilata per ARMv7 hard-float con CGO_ENABLED=0: solo stdlib,
// nessuna dipendenza dalla libc del target.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Valorizzata a build time da -ldflags -X (vedi hello-lyra.mk).
var version = "dev"

func main() {
	banner()

	section("Board")
	kv("Modello", boardModel())
	kv("Kernel", kernelRelease())
	kv("Uptime", uptime())

	section("Memoria")
	for _, l := range memory() {
		kv(l[0], l[1])
	}

	section("Partizioni MTD")
	mtd()

	fmt.Println()
}

func banner() {
	const line = "═══════════════════════════════════════════════════════"
	fmt.Println()
	fmt.Println(line)
	fmt.Printf("  hello-lyra %s — Luckfox Lyra Plus (RK3506G2)\n", version)
	fmt.Printf("  Buildroot upstream + external tree · %s\n",
		time.Now().Format("2006-01-02 15:04:05"))
	fmt.Println(line)
}

func section(name string) {
	fmt.Printf("\n  %s\n  %s\n", name, strings.Repeat("─", len(name)+2))
}

func kv(k, v string) {
	fmt.Printf("    %-14s %s\n", k+":", v)
}

// readFile legge un file di /proc restituendo un motivo leggibile in caso
// di errore, invece di far esplodere il programma: su una board in
// bring-up e' normale che qualcosa manchi, e sapere *cosa* manca e' il
// punto di questo programma.
func readFile(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	// I nodi di /proc/device-tree sono stringhe terminate da NUL.
	return strings.TrimRight(strings.TrimSpace(string(b)), "\x00"), nil
}

func boardModel() string {
	s, err := readFile("/proc/device-tree/model")
	if err != nil {
		return fmt.Sprintf("non leggibile (%v)", err)
	}
	return s
}

func kernelRelease() string {
	s, err := readFile("/proc/sys/kernel/osrelease")
	if err != nil {
		return fmt.Sprintf("non leggibile (%v)", err)
	}
	return s
}

func uptime() string {
	s, err := readFile("/proc/uptime")
	if err != nil {
		return fmt.Sprintf("non leggibile (%v)", err)
	}
	// Formato: "<secondi attivi> <secondi idle>"
	f := strings.Fields(s)
	if len(f) == 0 {
		return "formato inatteso: " + s
	}
	secs, err := strconv.ParseFloat(f[0], 64)
	if err != nil {
		return "formato inatteso: " + s
	}
	d := time.Duration(secs * float64(time.Second))
	return fmt.Sprintf("%s (%.2f s)", d.Round(time.Second), secs)
}

// memory estrae da /proc/meminfo le voci che contano in bring-up.
// MemAvailable e' la stima del kernel di quanto e' allocabile senza
// swappare: piu' onesta di MemFree su un sistema con page cache.
func memory() [][2]string {
	want := []string{"MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached"}
	found := map[string]string{}

	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return [][2]string{{"meminfo", fmt.Sprintf("non leggibile (%v)", err)}}
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		found[k] = humanKB(strings.TrimSpace(v))
	}

	out := make([][2]string, 0, len(want))
	for _, k := range want {
		if v, ok := found[k]; ok {
			out = append(out, [2]string{k, v})
		}
	}
	if len(out) == 0 {
		return [][2]string{{"meminfo", "nessuna voce riconosciuta"}}
	}
	return out
}

// humanKB converte "262144 kB" in "256.0 MiB (262144 kB)".
func humanKB(s string) string {
	f := strings.Fields(s)
	if len(f) == 0 {
		return s
	}
	kb, err := strconv.ParseFloat(f[0], 64)
	if err != nil {
		return s
	}
	return fmt.Sprintf("%.1f MiB (%s)", kb/1024, s)
}

// mtd stampa /proc/mtd. Se il file non c'e' non e' un errore fatale: nella
// variante initramfs il rootfs non sta su NAND e la UBI puo' non essere
// attaccata.
func mtd() {
	f, err := os.Open("/proc/mtd")
	if err != nil {
		fmt.Printf("    non leggibile (%v)\n", err)
		fmt.Println("    atteso su questa board: mtd0=uboot mtd1=boot mtd2=rootfs")
		return
	}
	defer f.Close()

	fmt.Printf("    %-8s %-12s %-12s %s\n", "dev", "size", "erasesize", "name")

	sc := bufio.NewScanner(f)
	n := 0
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "dev:") { // intestazione
			continue
		}
		// Formato: "mtd0: 00400000 00020000 \"uboot\""
		dev, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		fields := strings.Fields(rest)
		if len(fields) < 3 {
			continue
		}
		size := parseHexBytes(fields[0])
		erase := parseHexBytes(fields[1])
		name := strings.Trim(strings.Join(fields[2:], " "), "\"")
		fmt.Printf("    %-8s %-12s %-12s %s\n", dev, size, erase, name)
		n++
	}
	if n == 0 {
		fmt.Println("    nessuna partizione MTD: mtdparts= assente dal bootargs?")
	}
}

func parseHexBytes(s string) string {
	v, err := strconv.ParseUint(s, 16, 64)
	if err != nil {
		return s
	}
	switch {
	case v >= 1<<20:
		return fmt.Sprintf("%.0f MiB", float64(v)/(1<<20))
	case v >= 1<<10:
		return fmt.Sprintf("%.0f KiB", float64(v)/(1<<10))
	default:
		return fmt.Sprintf("%d B", v)
	}
}
