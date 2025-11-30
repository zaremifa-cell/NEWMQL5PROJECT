#!/usr/bin/env python3
"""
Adaptive Strategy with Currency Normalization
- Режим от последните 5 завършени снапшота
- Нормализация на посоката спрямо общата валута с новия символ
- Ако няма обща валута - директно L/S
- Играем САМО ако последният съвпада с режима
"""

import pandas as pd
import os

# Load all data
data_dir = "/Users/zlatkoanastasov/Documents/VSCode/MQL5"
files = ["Snapshots_v6_45.csv", "Snapshots_v6_47.csv", "Snapshots_vXIII.csv"]

all_data = []
for f in files:
    path = os.path.join(data_dir, f)
    if os.path.exists(path):
        df = pd.read_csv(path)
        all_data.append(df)
        print(f"Loaded {f}: {len(df)} rows")

combined = pd.concat(all_data, ignore_index=True)
print(f"\nTotal rows: {len(combined)}")

def get_currencies(symbol):
    """Extract base and quote currency from symbol"""
    return symbol[:3], symbol[3:]

def find_common_currency(sym1, sym2):
    """
    Find common currency between two symbols.
    Returns: (common_currency, position_in_sym1, position_in_sym2)
    position: 'base' or 'quote'
    """
    base1, quote1 = get_currencies(sym1)
    base2, quote2 = get_currencies(sym2)
    
    if base1 == base2:
        return base1, 'base', 'base'
    elif base1 == quote2:
        return base1, 'base', 'quote'
    elif quote1 == base2:
        return quote1, 'quote', 'base'
    elif quote1 == quote2:
        return quote1, 'quote', 'quote'
    else:
        return None, None, None

def normalize_direction(finished_dir, finished_symbol, target_symbol):
    """
    Normalize the direction of a finished snapshot relative to target symbol.
    
    If common currency is in SAME position (base-base or quote-quote) -> same direction
    If common currency is in DIFFERENT position (base-quote) -> flip direction
    If no common currency -> use direction as-is
    """
    common, pos1, pos2 = find_common_currency(finished_symbol, target_symbol)
    
    if common is None:
        # No common currency - use direction as-is
        return finished_dir
    
    if pos1 == pos2:
        # Same position - same direction
        return finished_dir
    else:
        # Different position - flip direction
        return 'S' if finished_dir == 'L' else 'L'

# Find finished snapshots (ShiftPct reached ±100)
finished = []
seen = {}  # Track last ShiftPct per symbol

for idx, row in combined.iterrows():
    symbol = row['Symbol']
    shiftpct = row['ShiftPct']
    
    # Check if this symbol just crossed ±100
    if symbol in seen:
        prev = seen[symbol]
        # Finished if crossed threshold
        if abs(prev) < 100 and abs(shiftpct) >= 100:
            direction = 'L' if shiftpct >= 100 else 'S'
            finished.append({
                'idx': idx,
                'symbol': symbol,
                'shiftpct': shiftpct,
                'direction': direction
            })
    
    seen[symbol] = shiftpct

print(f"\nTotal finished snapshots: {len(finished)}")

# Simulate with normalized filter
N = 5
trades = []
skipped_no_regime = 0
skipped_no_match = 0

for i in range(N, len(finished)):
    # Current snapshot (the one we're betting on)
    current = finished[i]
    target_symbol = current['symbol']
    
    # Last N finished snapshots
    last_n = finished[i-N:i]
    
    # Count normalized directions relative to target symbol
    long_count = 0
    short_count = 0
    
    for snap in last_n:
        norm_dir = normalize_direction(snap['direction'], snap['symbol'], target_symbol)
        if norm_dir == 'L':
            long_count += 1
        else:
            short_count += 1
    
    # Determine regime
    if long_count > short_count:
        regime = 'L'
    elif short_count > long_count:
        regime = 'S'
    else:
        skipped_no_regime += 1
        continue  # Tie - skip
    
    # Check if last (Nth) snapshot's normalized direction matches regime
    last_snap = last_n[-1]
    last_norm_dir = normalize_direction(last_snap['direction'], last_snap['symbol'], target_symbol)
    
    if last_norm_dir != regime:
        skipped_no_match += 1
        continue
    
    # Trade in the regime direction
    actual_direction = current['direction']
    actual_shiftpct = current['shiftpct']
    
    # Calculate PnL
    if regime == 'L':  # We bet LONG
        pnl = actual_shiftpct  # Positive if went LONG (+100)
    else:  # regime == 'S', we bet SHORT
        pnl = -actual_shiftpct  # Positive if went SHORT (-100)
    
    trades.append({
        'game': i,
        'symbol': target_symbol,
        'regime': regime,
        'actual': actual_direction,
        'shiftpct': actual_shiftpct,
        'pnl': pnl,
        'win': pnl > 0,
        'long_count': long_count,
        'short_count': short_count,
        'last_norm': last_norm_dir
    })

print(f"\nSkipped (tie): {skipped_no_regime}")
print(f"Skipped (last didn't match): {skipped_no_match}")
print(f"Total trades: {len(trades)}")

# Results
if trades:
    wins = sum(1 for t in trades if t['win'])
    losses = len(trades) - wins
    total_pnl = sum(t['pnl'] for t in trades)
    
    print(f"\n{'='*60}")
    print("ADAPTIVE STRATEGY WITH CURRENCY NORMALIZATION")
    print(f"{'='*60}")
    print(f"Total trades: {len(trades)}")
    print(f"Wins: {wins} ({100*wins/len(trades):.1f}%)")
    print(f"Losses: {losses} ({100*losses/len(trades):.1f}%)")
    print(f"Total PnL: {total_pnl:+.2f}%")
    print(f"Avg PnL per trade: {total_pnl/len(trades):+.2f}%")
    
    # Breakdown by regime
    print(f"\n{'='*60}")
    print("BY REGIME")
    print(f"{'='*60}")
    
    for r in ['L', 'S']:
        r_trades = [t for t in trades if t['regime'] == r]
        if r_trades:
            r_wins = sum(1 for t in r_trades if t['win'])
            r_pnl = sum(t['pnl'] for t in r_trades)
            regime_name = "LONG" if r == 'L' else "SHORT"
            print(f"{regime_name}: {len(r_trades)} trades, {r_wins} wins ({100*r_wins/len(r_trades):.1f}%), PnL: {r_pnl:+.2f}%")
    
    # Show some trades with normalization details
    print(f"\n{'='*60}")
    print("SAMPLE TRADES (first 20)")
    print(f"{'='*60}")
    for t in trades[:20]:
        regime_name = "LONG" if t['regime'] == 'L' else "SHORT"
        result = "WIN" if t['win'] else "LOSS"
        print(f"Game {t['game']:3d}: {t['symbol']:6s} | Regime={regime_name:5s} (L:{t['long_count']}/S:{t['short_count']}) | "
              f"Actual={t['shiftpct']:+7.2f}% | PnL={t['pnl']:+7.2f}% [{result}]")

# Compare with non-normalized version
print(f"\n{'='*60}")
print("COMPARISON: NON-NORMALIZED VS NORMALIZED")
print(f"{'='*60}")

# Non-normalized (original)
trades_non_norm = []
for i in range(N, len(finished)):
    current = finished[i]
    last_n = finished[i-N:i]
    
    longs = sum(1 for x in last_n if x['direction'] == 'L')
    shorts = N - longs
    
    if longs > shorts:
        regime = 'L'
    elif shorts > longs:
        regime = 'S'
    else:
        continue
    
    last_one = last_n[-1]
    if last_one['direction'] != regime:
        continue
    
    actual_shiftpct = current['shiftpct']
    if regime == 'L':
        pnl = actual_shiftpct
    else:
        pnl = -actual_shiftpct
    
    trades_non_norm.append({'pnl': pnl, 'win': pnl > 0})

non_norm_wins = sum(1 for t in trades_non_norm if t['win'])
non_norm_pnl = sum(t['pnl'] for t in trades_non_norm)
norm_wins = sum(1 for t in trades if t['win'])
norm_pnl = sum(t['pnl'] for t in trades)

print(f"Non-Normalized: {len(trades_non_norm)} trades, {non_norm_wins} wins ({100*non_norm_wins/len(trades_non_norm):.1f}%), PnL: {non_norm_pnl:+.2f}%")
print(f"Normalized:     {len(trades)} trades, {norm_wins} wins ({100*norm_wins/len(trades):.1f}%), PnL: {norm_pnl:+.2f}%")
