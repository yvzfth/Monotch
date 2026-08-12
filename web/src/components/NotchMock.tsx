/**
 * A static illustration of the expanded island. It paints its own dark surface
 * and fixed colours so it reads as a screenshot rather than a page element.
 */
export default function NotchMock() {
  return (
    <div className="sticker rounded-card bg-[#0b0b0c] p-3 shadow-[8px_8px_0_0_var(--color-ink)]">
      <div className="rounded-[1.25rem] bg-[#141416] p-4">
        <div className="flex items-center gap-2">
          {["bg-lemon", "bg-sky", "bg-lime", "bg-grape"].map((accent, index) => (
            <span
              key={accent}
              className={`h-6 w-6 rounded-lg ${accent} ${index === 0 ? "" : "opacity-30"}`}
            />
          ))}
          <span className="ml-auto text-[10px] font-medium tracking-widest text-white/35">
            MONOTCH
          </span>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <span className="h-14 w-14 shrink-0 rounded-xl bg-gradient-to-br from-grape to-coral" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold text-white/90">
              Everything In Its Right Place
            </p>
            <p className="truncate text-xs text-white/45">Radiohead — Kid A</p>
            <div className="mt-2.5 h-1 rounded-full bg-white/12">
              <div className="h-1 w-1/3 rounded-full bg-lemon" />
            </div>
          </div>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-2">
          {[
            { label: "CPU", value: "18%" },
            { label: "RAM", value: "9.4 GB" },
            { label: "FANS", value: "1980" },
          ].map((stat) => (
            <div key={stat.label} className="rounded-xl bg-white/6 px-2.5 py-2">
              <p className="text-[9px] font-bold tracking-wider text-white/35">
                {stat.label}
              </p>
              <p className="mt-1 text-sm font-semibold text-white/85">{stat.value}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
