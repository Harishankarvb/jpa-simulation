using JosephsonCircuits
using Plots

# ── Symbolic variables ──────────────────────────────────────
@variables R Cc Cj Lj Cr Lr L1 Ldc K Lg

# ── Circuit netlist ──────────────────────────────────────────
circuit = [
    ("P1","1","0",1),
    ("R1","1","0",R),
    ("L0","1","0",Lg),
    ("C1","1","2",Cc),
    ("L1","2","3",Lr),
    ("C2","2","0",Cr),
    ("Lj1","3","0",Lj),
    ("Cj1","3","0",Cj),
    ("L2","3","4",L1),
    ("Lj2","4","0",Lj),
    ("Cj2","4","0",Cj),
    ("L3","5","0",Ldc),
    ("K1","L2","L3",K),
    ("P2","5","0",2),
    ("R2","5","0",1000.0),
]

# ── Component values ─────────────────────────────────────────
circuitdefs = Dict(
    Lj  => 219.63e-12,
    Lr  => 0.4264e-9,
    Lg  => 100.0e-9,
    Cc  => 25.0e-15,
    Cj  => 10.0e-15,
    Cr  => 0.758e-12,     # adjusted for ~7 GHz
    R   => 50.0,
    L1  => 34e-12,
    K   => 0.999,
    Ldc => 0.74e-12,
)

# ── Fixed parameters ─────────────────────────────────────────
Idc  = 142.0e-6
Phi0 = 2.067833848e-15
M    = 0.999 * sqrt(34e-12 * 0.74e-12)

# ════════════════════════════════════════════════════════════
# AUTO-FIND BEST wp AND Ip
# ════════════════════════════════════════════════════════════

best_gain = 0.0
best_wp   = 14.0
best_Ip   = 10.5e-6

ws_search = 2*pi*(6.5:0.005:7.5)*1e9   

for wp_test in range(13.60, 14.0, length=25)
    for Ip_test in range(5.0e-6, 15.0e-6, length=15)

        sources_test = [
            (mode=(0,), port=2, current=Idc),
            (mode=(1,), port=2, current=Ip_test)
        ]

        try
            sol = hbsolve(
                ws_search, (2*pi*wp_test*1e9,), sources_test,
                (4,), (8,),    
                circuit, circuitdefs,
                dc=true, threewavemixing=true, fourwavemixing=true
            )

            g = 10*log10.(abs2.(
                sol.linearized.S(
                    outputmode=(0,), outputport=1,
                    inputmode=(0,),  inputport=1,
                    freqindex=:
                )
            ))

            peak_g = maximum(g)

            if peak_g > best_gain
                global best_gain = peak_g
                global best_wp   = wp_test
                global best_Ip   = Ip_test
            end

            println("wp = $(round(wp_test, digits=3)) GHz | " *
                    "Ip = $(round(Ip_test*1e6, digits=1)) uA | " *
                    "gain = $(round(peak_g, digits=2)) dB")

        catch e
            println("wp = $(round(wp_test, digits=3)) GHz | " *
                    "Ip = $(round(Ip_test*1e6, digits=1)) uA | " *
                    "no convergence")
        end
    end
end

println("\n" * "=" ^60)
println("BEST FOUND:")
println("  wp   = $(round(best_wp, digits=3)) GHz")
println("  Ip   = $(round(best_Ip*1e6, digits=2)) uA")
println("  gain = $(round(best_gain, digits=2)) dB")
println("=" ^60)

wp = (2*pi*best_wp*1e9,)
Ip = best_Ip

# ════════════════════════════════════════════════════════════
#   PART 1 — GAIN CURVE (using optimal wp and Ip)
# ════════════════════════════════════════════════════════════

println("\n" * "=" ^60)
println("PART 1: Running gain curve with optimal parameters...")
println("=" ^60)

ws = 2*pi*(6.5:0.0001:7.5)*1e9

sourcespumpon = [
    (mode=(0,), port=2, current=Idc),
    (mode=(1,), port=2, current=Ip)
]

Npumpharmonics      = (16,)
Nmodulationharmonics = (8,)

@time jpapumpon = hbsolve(
    ws, wp, sourcespumpon,
    Nmodulationharmonics, Npumpharmonics,
    circuit, circuitdefs,
    dc=true, threewavemixing=true, fourwavemixing=true
)

# Extract gain
gain_dB = 10*log10.(abs2.(
    jpapumpon.linearized.S(
        outputmode=(0,),
        outputport=1,
        inputmode=(0,),
        inputport=1,
        freqindex=:
    )
))

freq_GHz = jpapumpon.linearized.w / (2*pi*1e9)

# Peak gain and bandwidth
peak_gain  = maximum(gain_dB)
peak_freq  = freq_GHz[argmax(gain_dB)]
bw_mask    = gain_dB .>= (peak_gain - 3.0)
bandwidth  = (maximum(freq_GHz[bw_mask]) - minimum(freq_GHz[bw_mask])) * 1e3

println("\nGain Curve Results:")
println("  Peak gain     : $(round(peak_gain, digits=2)) dB")
println("  Peak frequency: $(round(peak_freq, digits=4)) GHz")
println("  3dB bandwidth : $(round(bandwidth, digits=2)) MHz")

# Plot gain curve
p1 = plot(
    freq_GHz,
    gain_dB,
    xlabel="Frequency (GHz)",
    ylabel="Gain (dB)",
    title="JPA Gain Curve (~7 GHz)",
    label="JPA Gain",
    linewidth=2,
    color=:red,
)
scatter!(p1,
    [peak_freq], [peak_gain],
    label="Peak: $(round(peak_gain,digits=1)) dB @ $(round(peak_freq,digits=4)) GHz",
    markersize=6,
    color=:darkblue
)
hline!(p1,
    [peak_gain - 3.0],
    label="3dB level — BW = $(round(bandwidth,digits=2)) MHz",
    linestyle=:dash,
    color=:green
)

# ════════════════════════════════════════════════════════════
#   PART 2 — FLUX TUNING CURVE
# ════════════════════════════════════════════════════════════

println("\n" * "=" ^60)
println("PART 2: Running flux tuning curve simulation...")
println("=" ^60)

ws_flux    = 2*pi*(5.0:0.005:12.0)*1e9
Ip_flux    = 0.7e-6 
Idc_values = range(5e-6, 260e-6, length=150)

resonant_freqs = Float64[]
flux_values    = Float64[]

for Idc_sweep in Idc_values

    local sourcespumpon_flux = [
        (mode=(0,), port=2, current=Idc_sweep),
        (mode=(1,), port=2, current=Ip_flux)
    ]

    try
        sol = hbsolve(
            ws_flux, wp, sourcespumpon_flux,
            (4,), (8,),
            circuit, circuitdefs,
            dc=true, threewavemixing=true, fourwavemixing=true
        )

        gain_dB_flux = 10*log10.(abs2.(
            sol.linearized.S(
                outputmode=(0,),
                outputport=1,
                inputmode=(0,),
                inputport=1,
                freqindex=:
            )
        ))

        freq_GHz_flux = sol.linearized.w / (2*pi*1e9)
        peak_idx      = argmax(gain_dB_flux)

        push!(resonant_freqs, freq_GHz_flux[peak_idx])
        push!(flux_values,    (M * Idc_sweep) / Phi0)

        println("Idc = $(round(Idc_sweep*1e6, digits=1)) uA | " *
                "flux = $(round((M*Idc_sweep)/Phi0, digits=3)) Phi0 | " *
                "f_res = $(round(freq_GHz_flux[peak_idx], digits=4)) GHz")

    catch e
        println("No convergence at Idc = $(round(Idc_sweep*1e6, digits=1)) uA")
    end
end

# Filter clean left half
clean_mask = flux_values .<= 0.48
flux_clean = flux_values[clean_mask]
freq_clean = resonant_freqs[clean_mask]

# Remove duplicates
unique_idx = unique(i -> flux_clean[i], 1:length(flux_clean))
flux_clean = flux_clean[unique_idx]
freq_clean = freq_clean[unique_idx]

# Mirror to get right half
flux_mirror = 1.0 .- reverse(flux_clean)
freq_mirror = reverse(freq_clean)

# Combine and sort
flux_full  = vcat(flux_clean, flux_mirror)
freq_full  = vcat(freq_clean, freq_mirror)
sorted_idx = sortperm(flux_full)
flux_full  = flux_full[sorted_idx]
freq_full  = freq_full[sorted_idx]

println("\nFlux Tuning Results:")
println("  Min frequency : $(round(minimum(freq_full), digits=3)) GHz")
println("  Max frequency : $(round(maximum(freq_full), digits=3)) GHz")
println("  Tuning range  : $(round(maximum(freq_full)-minimum(freq_full), digits=3)) GHz")

# Plot flux tuning curve
p2 = plot(
    flux_full,
    freq_full,
    xlabel="External Flux (Phi_ext/Phi_0)",
    ylabel="Frequency (GHz)",
    title="JPA Flux-Frequency Curve",
    label="JPA tuning curve",
    linewidth=2,
    color=:purple,
    ylims=(5, 12),
    xlims=(0, 1)
)

# ════════════════════════════════════════════════════════════
#   FINAL — DISPLAY ALL PLOTS
# ════════════════════════════════════════════════════════════

println("\n" * "=" ^60)
println("FINAL SUMMARY")
println("=" ^60)
println("  Best wp          : $(round(best_wp, digits=3)) GHz")
println("  Best Ip          : $(round(best_Ip*1e6, digits=2)) uA")
println("  Peak gain        : $(round(peak_gain, digits=2)) dB")
println("  Peak frequency   : $(round(peak_freq, digits=4)) GHz")
println("  3dB bandwidth    : $(round(bandwidth, digits=2)) MHz")
println("  Idc              : $(round(Idc*1e6, digits=1)) uA")

display(p1)
display(p2)
