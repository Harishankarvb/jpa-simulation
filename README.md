# jpa-simulation
Josephsons parametric amplifier (JPA) design and simulation for 7 GHz operation using JosephsonCircuits.jl

## ✨ Features

### 🔄 Automated Parameter Optimization (Auto-Tune)
Replaces error-prone manual sweeping with a grid search that finds the gain-maximizing operating point automatically:
- Searches a grid of pump frequencies (`wp`) and pump currents (`Ip`)
- Runs `hbsolve()` at each grid point and records the peak gain
- Catches and skips non-convergent points (e.g., near bifurcation) via `try/catch`, so the sweep completes robustly even when individual points fail
- Reports the best-performing `(wp, Ip)` combination

> Example: a 25×15 grid search (375 combinations) was used to retune the design from a 9.75 GHz baseline to 7 GHz operation, converging on `wp ≈ 14.00 GHz`, `Ip ≈ 5.71 µA` — yielding **21.3 dB gain** at **6.9989 GHz** with **18 MHz** bandwidth.

### 📈 Flux Tuning Curve Generation
- Sweeps DC bias current and extracts the resonant frequency at each point (via the gain-curve argmax)
- Converts bias current to normalized flux Φ/Φ₀ using the flux quantum
- Exploits the circuit's inherent symmetry to mirror the curve beyond the solver's reliable range (~0.48 Φ₀), producing a full tuning curve from a half-sweep
  
