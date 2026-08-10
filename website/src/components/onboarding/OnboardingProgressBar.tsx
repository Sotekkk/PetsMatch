export function OnboardingProgressBar({ current, labels }: { current: number; labels: string[] }) {
  return (
    <div className="flex items-center w-full">
      {labels.map((label, i) => {
        const step = i + 1;
        const done = step < current;
        const active = step === current;
        return (
          <div key={label} className="flex items-center flex-1 last:flex-none">
            <div className="flex flex-col items-center gap-1 w-14 shrink-0">
              <div
                className={`w-6 h-6 rounded-full flex items-center justify-center text-[11px] font-bold border-2 ${
                  done || active
                    ? 'bg-[#6E9E57] border-[#6E9E57] text-white'
                    : 'bg-white border-gray-300 text-gray-400'
                }`}
              >
                {done ? '✓' : step}
              </div>
              <span
                className={`text-[10px] text-center leading-tight ${
                  active ? 'text-[#1F2A2E] font-bold' : 'text-gray-400 font-medium'
                }`}
              >
                {label}
              </span>
            </div>
            {i < labels.length - 1 && (
              <div className={`h-0.5 flex-1 mx-1 ${step < current ? 'bg-[#6E9E57]' : 'bg-gray-300'}`} />
            )}
          </div>
        );
      })}
    </div>
  );
}
