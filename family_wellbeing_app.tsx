import React, { useState, useEffect, useMemo } from 'react';
import { 
  Settings, RefreshCw, Check, Clock, User, 
  Smartphone, Database, AlertCircle, BarChart2, 
  ChevronRight, Shield, Zap, Info, Activity,
  ChevronDown
} from 'lucide-react';

// ============================================================================
// --- /src/models/Schema.js ---
// ============================================================================
// Emulating the MongoDB Atlas data models as described in the plan.

const MEMBERS = [
  { id: '1', name: 'Arun (You)', deviceModel: 'Pixel 8', avatarColor: '#D85A30' },
  { id: '2', name: 'Priya', deviceModel: 'Samsung S23', avatarColor: '#4A5568' },
  { id: '3', name: 'Rohan', deviceModel: 'OnePlus 11', avatarColor: '#2B6CB0' },
  { id: '4', name: 'Aarav', deviceModel: 'Pixel 7a', avatarColor: '#38A169' },
  { id: '5', name: 'Neha', deviceModel: 'Samsung A54', avatarColor: '#D69E2E' },
  { id: '6', name: 'Vikram', deviceModel: 'Nothing Phone 2', avatarColor: '#E53E3E' },
  { id: '7', name: 'Ananya', deviceModel: 'Pixel 6', avatarColor: '#805AD5' },
  { id: '8', name: 'Karan', deviceModel: 'Samsung Z Flip', avatarColor: '#319795' },
  { id: '9', name: 'Sneha', deviceModel: 'Moto Edge', avatarColor: '#DD6B20' },
  { id: '10', name: 'Aditya', deviceModel: 'Pixel 8 Pro', avatarColor: '#718096' },
  { id: '11', name: 'Riya', deviceModel: 'Samsung S22', avatarColor: '#3182CE' },
  { id: '12', name: 'Sanjay', deviceModel: 'OnePlus Nord', avatarColor: '#38A169' },
];

// ============================================================================
// --- /src/utils/DateUtils.js ---
// ============================================================================
// We simulate current dates for the mock application environment
const getTodayString = () => '2026-07-01'; 
const getYesterdayString = () => '2026-06-30'; 
const getLast7Days = () => {
  return [
    '2026-06-25', '2026-06-26', '2026-06-27', '2026-06-28', 
    '2026-06-29', '2026-06-30', '2026-07-01'
  ];
};

const formatTime = (minutes) => {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  return `${h}h ${m}m`;
};

// ============================================================================
// --- /src/services/MockDatabase.js ---
// ============================================================================
// Generates realistic usage records matching the schema
const generateInitialDatabase = () => {
  const db = [];
  const apps = ["Instagram", "WhatsApp", "YouTube", "Chrome", "Notion", "Spotify", "Maps"];
  
  MEMBERS.forEach(member => {
    getLast7Days().forEach(date => {
      const isToday = date === getTodayString();
      const totalMins = isToday 
        ? Math.floor(Math.random() * 180) + 10  // Incomplete today
        : Math.floor(Math.random() * 300) + 60; // Complete past days
        
      // Generate a realistic breakdown that adds up to totalMins
      let remaining = totalMins;
      const breakdown = [];
      const userApps = [...apps].sort(() => 0.5 - Math.random()).slice(0, 3); // Pick 3 random apps
      
      userApps.forEach((appName, index) => {
        if (index === userApps.length - 1) {
          breakdown.push({ appName, minutes: remaining });
        } else {
          const mins = Math.floor(Math.random() * (remaining * 0.7));
          breakdown.push({ appName, minutes: mins });
          remaining -= mins;
        }
      });
      
      breakdown.sort((a, b) => b.minutes - a.minutes); // Sort by highest usage

      db.push({
        _id: `${member.id}_${date}`,
        memberId: member.id,
        date: date,
        totalScreenTimeMinutes: totalMins,
        isComplete: !isToday,
        appBreakdown: breakdown
      });
    });
  });
  return db;
};

let MOCK_DB = generateInitialDatabase();

// ============================================================================
// --- /src/components/ui/SystemComponents.jsx ---
// ============================================================================

const Card = ({ children, className = "" }) => (
  <div className={`bg-white border border-zinc-200 rounded-2xl p-5 ${className}`}>
    {children}
  </div>
);

const Badge = ({ children, status = "neutral" }) => {
  const styles = {
    neutral: "bg-zinc-100 text-zinc-600 border-zinc-200",
    success: "bg-emerald-50 text-emerald-700 border-emerald-200",
    warning: "bg-amber-50 text-amber-700 border-amber-200",
    accent: "bg-[#FDF2F0] text-[#D85A30] border-[#F4E1DB]" // Warm clay accent
  };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[10px] font-medium tracking-wide uppercase border ${styles[status]}`}>
      {children}
    </span>
  );
};

// ============================================================================
// --- /src/services/SyncEngine.js ---
// ============================================================================
// Simulates the Android WorkManager daily job pulling from UsageStatsManager

const performUpsertSync = async (myMemberId) => {
  return new Promise((resolve) => {
    setTimeout(() => {
      // Fetch current local usage stats (simulated increase for today)
      const todayRecord = MOCK_DB.find(r => r._id === `${myMemberId}_${getTodayString()}`);
      if(todayRecord) {
        const newTodayMinutes = todayRecord.totalScreenTimeMinutes + 15;

        // "Upsert" logic - overwriting with _id
        MOCK_DB = MOCK_DB.map(record => {
          if (record._id === `${myMemberId}_${getTodayString()}`) {
            const newBreakdown = [...record.appBreakdown];
            if (newBreakdown.length > 0) newBreakdown[0].minutes += 15; // Add time to top app
            return { ...record, totalScreenTimeMinutes: newTodayMinutes, appBreakdown: newBreakdown, isComplete: false };
          }
          return record;
        });
      }
      resolve({ success: true, timestamp: new Date().toISOString() });
    }, 1500); // Simulate network latency
  });
};

// ============================================================================
// --- /src/features/dashboard/DashboardView.jsx ---
// ============================================================================

const DashboardView = ({ db, myId }) => {
  const myToday = db.find(r => r._id === `${myId}_${getTodayString()}`);

  return (
    <div className="flex flex-col gap-6 animate-in fade-in duration-300 pb-20">
      
      <div>
        <h2 className="text-2xl font-semibold text-zinc-900 tracking-tight">Overview</h2>
        <p className="text-sm text-zinc-500 mt-1">Your screen time today.</p>
      </div>

      <Card className="flex flex-col items-center justify-center py-10 relative overflow-hidden bg-white shadow-[0_2px_12px_-4px_rgba(0,0,0,0.05)] border-zinc-200/60">
        <div className="absolute top-0 right-0 p-4 opacity-5">
          <Activity size={120} />
        </div>
        <span className="text-xs font-medium text-zinc-400 uppercase tracking-widest mb-2 z-10">Today (Live)</span>
        <div className="text-6xl font-bold tracking-tighter text-zinc-900 z-10">
          {formatTime(myToday?.totalScreenTimeMinutes || 0)}
        </div>
      </Card>

      <div className="space-y-3">
        <h3 className="text-sm font-medium text-zinc-900 px-1">App Breakdown</h3>
        <Card className="!p-0 overflow-hidden shadow-sm border-zinc-200/60">
          <div className="divide-y divide-zinc-100">
            {myToday?.appBreakdown.map((app, idx) => (
              <div key={idx} className="flex justify-between items-center p-4 bg-white hover:bg-zinc-50 transition-colors">
                <span className="text-sm font-medium text-zinc-700">{app.appName}</span>
                <span className="text-sm font-mono text-zinc-900">{formatTime(app.minutes)}</span>
              </div>
            ))}
            {(!myToday?.appBreakdown || myToday.appBreakdown.length === 0) && (
              <div className="p-4 text-center text-sm text-zinc-500">No app data recorded yet today.</div>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
};

// ============================================================================
// --- /src/features/leaderboard/LeaderboardView.jsx ---
// ============================================================================

const LeaderboardView = ({ db, myId }) => {
  const [timeframe, setTimeframe] = useState('today'); // 'today' or 'weekly'
  const [expandedUserId, setExpandedUserId] = useState(null);

  // Join DB records with Member metadata and aggregate/sort (Lower is better)
  const rankedData = useMemo(() => {
    return MEMBERS.map(member => {
      let totalMinutes = 0;
      let combinedBreakdown = {};
      let isComplete = true;

      if (timeframe === 'today') {
        const record = db.find(r => r._id === `${member.id}_${getTodayString()}`);
        totalMinutes = record?.totalScreenTimeMinutes || 0;
        isComplete = record?.isComplete || false;
        
        (record?.appBreakdown || []).forEach(app => {
          combinedBreakdown[app.appName] = (combinedBreakdown[app.appName] || 0) + app.minutes;
        });
      } else {
        // Weekly: Sum up all 7 days
        getLast7Days().forEach(date => {
          const record = db.find(r => r._id === `${member.id}_${date}`);
          if (record) {
            totalMinutes += record.totalScreenTimeMinutes;
            (record.appBreakdown || []).forEach(app => {
              combinedBreakdown[app.appName] = (combinedBreakdown[app.appName] || 0) + app.minutes;
            });
            if (!record.isComplete && date !== getTodayString()) {
              isComplete = false; 
            }
          }
        });
      }

      // Convert combined breakdown object back to sorted array
      const sortedBreakdown = Object.entries(combinedBreakdown)
        .map(([appName, minutes]) => ({ appName, minutes }))
        .sort((a, b) => b.minutes - a.minutes);

      return {
        ...member,
        minutes: totalMinutes,
        isComplete,
        appBreakdown: sortedBreakdown
      };
    }).sort((a, b) => a.minutes - b.minutes); // Ascending order (lowest time wins)
  }, [db, timeframe]);

  return (
    <div className="flex flex-col h-full animate-in fade-in duration-300">
      
      <div className="mb-6">
        <h2 className="text-2xl font-semibold text-zinc-900 tracking-tight">Leaderboard</h2>
        <p className="text-sm text-zinc-500 mt-1">Lower screen time ranks higher.</p>
      </div>

      {/* Segmented Control */}
      <div className="flex gap-2 mb-6 border-b border-zinc-200 pb-2">
        <button 
          onClick={() => setTimeframe('today')}
          className={`text-sm font-medium pb-2 -mb-[9px] border-b-2 transition-colors ${timeframe === 'today' ? 'border-zinc-900 text-zinc-900' : 'border-transparent text-zinc-500 hover:text-zinc-700'}`}
        >
          Today
        </button>
        <button 
          onClick={() => setTimeframe('weekly')}
          className={`text-sm font-medium pb-2 -mb-[9px] border-b-2 transition-colors ${timeframe === 'weekly' ? 'border-zinc-900 text-zinc-900' : 'border-transparent text-zinc-500 hover:text-zinc-700'}`}
        >
          This Week
        </button>
      </div>

      <div className="flex-1 overflow-y-auto pr-2 space-y-3 pb-24">
        {rankedData.map((user, index) => {
          const isWinner = index === 0;
          const maxMinutes = timeframe === 'today' ? 400 : 2800; // Adjust scale for week
          const percentage = Math.min((user.minutes / maxMinutes) * 100, 100);
          const isMe = user.id === myId;
          const isExpanded = expandedUserId === user.id;

          return (
            <div key={user.id} className="flex flex-col gap-0">
              <div 
                onClick={() => setExpandedUserId(isExpanded ? null : user.id)}
                className={`flex items-center gap-4 p-3 rounded-2xl border cursor-pointer transition-colors ${isMe ? 'bg-zinc-50 border-zinc-200 shadow-sm' : 'bg-white border-zinc-200/60 hover:border-zinc-300'} ${isExpanded ? 'rounded-b-none border-b-transparent' : ''}`}
              >
                
                <div className="w-5 text-center font-mono text-xs text-zinc-400">
                  {index + 1}
                </div>
                
                <div 
                  className="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-medium shadow-sm"
                  style={{ backgroundColor: user.avatarColor }}
                >
                  {user.name.charAt(0)}
                </div>
                
                <div className="flex-1">
                  <div className="flex justify-between items-end mb-1.5">
                    <div className="flex items-center gap-2">
                      <span className={`text-sm font-medium ${isMe ? 'text-zinc-900' : 'text-zinc-700'}`}>
                        {user.name}
                      </span>
                      {isWinner && <Badge status="accent">Leader</Badge>}
                    </div>
                    <div className="flex items-center gap-2">
                      <span className={`font-mono text-sm ${isMe ? 'text-zinc-900 font-semibold' : 'text-zinc-600'}`}>
                        {formatTime(user.minutes)}
                      </span>
                      <ChevronDown size={14} className={`text-zinc-400 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
                    </div>
                  </div>
                  
                  {/* Progress bar */}
                  <div className="h-1 w-full bg-zinc-100 rounded-full overflow-hidden">
                    <div 
                      className={`h-full rounded-full transition-all duration-1000 ${isWinner ? 'bg-[#D85A30]' : (isMe ? 'bg-zinc-800' : 'bg-zinc-300')}`} 
                      style={{ width: `${percentage}%` }}
                    />
                  </div>
                </div>
              </div>
              
              {/* Expandable App Breakdown Section */}
              {isExpanded && (
                <div className="bg-zinc-50/50 border border-zinc-200 border-t-0 rounded-b-2xl p-4 pt-2 mb-2 animate-in slide-in-from-top-2 duration-200">
                  <div className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider mb-3 px-1">App Breakdown</div>
                  <div className="space-y-2">
                    {user.appBreakdown.slice(0, 4).map((app, idx) => (
                      <div key={idx} className="flex justify-between items-center px-1">
                        <span className="text-xs text-zinc-600">{app.appName}</span>
                        <span className="text-xs font-mono text-zinc-500">{formatTime(app.minutes)}</span>
                      </div>
                    ))}
                    {user.appBreakdown.length === 0 && (
                      <div className="text-xs text-zinc-400 px-1 italic">No app data recorded.</div>
                    )}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

// ============================================================================
// --- /src/features/settings/SettingsView.jsx ---
// ============================================================================

const SettingsView = ({ onClose, profile, setProfile }) => (
  <div className="flex flex-col h-full animate-in slide-in-from-right-4 duration-300 pb-20">
    <div className="flex items-center gap-3 mb-8">
      <button onClick={onClose} className="p-1 hover:bg-zinc-100 rounded-lg transition-colors text-zinc-500">
        <ChevronRight size={20} className="rotate-180" />
      </button>
      <div>
        <h2 className="text-xl font-semibold text-zinc-900 tracking-tight">Settings</h2>
      </div>
    </div>

    <div className="space-y-8">
      
      <section>
        <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider mb-3 px-1">My Profile</h3>
        <Card className="space-y-4 shadow-sm border-zinc-200/60">
          <div>
            <label className="block text-sm font-medium text-zinc-700 mb-1.5">Display Name</label>
            <input 
              type="text"
              value={profile.name}
              onChange={(e) => setProfile({...profile, name: e.target.value})}
              className="w-full bg-zinc-50 border border-zinc-200 rounded-xl p-3 text-sm outline-none focus:border-zinc-400 text-zinc-900 transition-colors"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-zinc-700 mb-1.5">Device Name</label>
            <input 
              type="text"
              value={profile.device}
              onChange={(e) => setProfile({...profile, device: e.target.value})}
              className="w-full bg-zinc-50 border border-zinc-200 rounded-xl p-3 text-sm outline-none focus:border-zinc-400 text-zinc-900 transition-colors"
            />
          </div>
        </Card>
      </section>

      <section>
        <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider mb-3 px-1">Database Connection</h3>
        <Card className="space-y-4 shadow-sm border-zinc-200/60">
          <div>
            <label className="block text-sm font-medium text-zinc-700 mb-1.5">MongoDB Atlas URI</label>
            <input 
              type="password"
              defaultValue="mongodb+srv://family:*****@cluster0.mongodb.net/wellbeing"
              className="w-full bg-zinc-50 border border-zinc-200 rounded-xl p-3 text-sm outline-none focus:border-zinc-400 font-mono text-zinc-600 transition-colors"
            />
            <p className="text-[11px] text-zinc-500 mt-2 flex items-center gap-1">
              <Shield size={12} /> Stored in Android EncryptedSharedPreferences.
            </p>
          </div>
        </Card>
      </section>

      <section>
        <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider mb-3 px-1">Permissions</h3>
        <div className="space-y-2">
          <Card className="flex flex-col gap-2 !p-4 shadow-sm border-zinc-200/60">
            <div className="flex justify-between items-start">
              <div>
                <div className="text-sm font-medium text-zinc-900 flex items-center gap-1.5">
                  <Activity size={14} /> PACKAGE_USAGE_STATS
                </div>
                <div className="text-xs text-zinc-500 mt-1 pr-4">Required to read screen time via UsageStatsManager.</div>
              </div>
              <Badge status="success">Granted</Badge>
            </div>
          </Card>
      </div>
    </section>

  </div>
</div>
);

// ============================================================================
// --- /src/App.jsx --- (Main Wiring & Layout)
// ============================================================================

export default function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [db, setDb] = useState(MOCK_DB);
  const [lastSynced, setLastSynced] = useState(null);
  const [isSyncing, setIsSyncing] = useState(false);
  
  const MY_ID = '1'; 

  const [profile, setProfile] = useState({
    name: MEMBERS.find(m => m.id === MY_ID).name,
    device: MEMBERS.find(m => m.id === MY_ID).deviceModel
  });

  // Background silent sync on app mount
  useEffect(() => {
    const runBackgroundSync = async () => {
      setIsSyncing(true);
      await performUpsertSync(MY_ID);
      setDb([...MOCK_DB]);
      setLastSynced(new Date());
      setIsSyncing(false);
    };
    runBackgroundSync();
  }, []);

  // Sync profile edits back to the global members list
  useEffect(() => {
    const me = MEMBERS.find(m => m.id === MY_ID);
    if (me) {
      me.name = profile.name;
      me.deviceModel = profile.device;
    }
  }, [profile]);

  return (
    <div className="min-h-screen bg-[#EBEBEB] flex items-center justify-center p-4 sm:p-8 font-sans selection:bg-zinc-200">
      
      {/* Container simulating a phone screen, but styled like a clean web app */}
      <div className="w-full max-w-[400px] h-[800px] bg-[#FAFAFA] rounded-[36px] shadow-2xl border-[10px] border-zinc-800 flex flex-col relative overflow-hidden">
        
        {/* Top Header Bar */}
        <header className="px-6 pt-10 pb-4 flex justify-between items-center bg-[#FAFAFA] z-20 border-b border-zinc-100/50">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-zinc-900 flex items-center justify-center">
              <Activity size={16} className="text-white" />
            </div>
            <h1 className="text-lg font-semibold tracking-tight text-zinc-900">Wellbeing</h1>
          </div>
          
          <button 
            onClick={() => setActiveTab(activeTab === 'settings' ? 'dashboard' : 'settings')}
            className={`w-9 h-9 rounded-full border flex items-center justify-center transition-all ${activeTab === 'settings' ? 'border-zinc-900 bg-zinc-900 text-white shadow-md' : 'border-zinc-200 bg-white hover:bg-zinc-50 text-zinc-600'}`}
          >
            {activeTab === 'settings' ? <ChevronDown size={18} /> : <User size={16} />}
          </button>
        </header>

        {/* Scrollable Main Content Area */}
        <main className="flex-1 overflow-y-auto px-6 pt-6 bg-[#FAFAFA]">
          {activeTab === 'dashboard' && (
            <DashboardView db={db} myId={MY_ID} />
          )}
          {activeTab === 'leaderboard' && (
            <LeaderboardView db={db} myId={MY_ID} />
          )}
          {activeTab === 'settings' && (
            <SettingsView 
              onClose={() => setActiveTab('dashboard')} 
              profile={profile}
              setProfile={setProfile}
            />
          )}
        </main>

        {/* Subtle background sync status indicator (Hidden on Settings) */}
        {activeTab !== 'settings' && (
           <div className="absolute bottom-20 left-0 right-0 flex justify-center pointer-events-none z-10 animate-in fade-in duration-700">
             <div className="flex items-center gap-1.5 bg-[#FAFAFA]/90 backdrop-blur-md px-4 py-1.5 rounded-full border border-zinc-200/50 shadow-sm">
                {isSyncing ? (
                  <RefreshCw size={10} className="text-zinc-400 animate-spin" />
                ) : (
                  <Check size={10} className="text-zinc-400" />
                )}
                <span className="text-[10px] font-mono text-zinc-500">
                  {isSyncing ? 'syncing...' : `synced ${lastSynced?.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) || ''}`}
                </span>
             </div>
           </div>
        )}

        {/* Minimal Bottom Navigation */}
        <div className="absolute bottom-0 left-0 right-0 bg-white/95 backdrop-blur-md border-t border-zinc-200 h-16 flex px-6 items-center justify-around z-20">
          <button 
            onClick={() => setActiveTab('dashboard')}
            className={`flex flex-col items-center gap-1 w-16 transition-colors ${activeTab === 'dashboard' ? 'text-zinc-900' : 'text-zinc-400 hover:text-zinc-600'}`}
          >
            <Activity size={18} />
            <span className="text-[10px] font-medium tracking-wide">Overview</span>
          </button>
          
          <div className="w-[1px] h-6 bg-zinc-200"></div>
          
          <button 
            onClick={() => setActiveTab('leaderboard')}
            className={`flex flex-col items-center gap-1 w-16 transition-colors ${activeTab === 'leaderboard' ? 'text-zinc-900' : 'text-zinc-400 hover:text-zinc-600'}`}
          >
            <BarChart2 size={18} />
            <span className="text-[10px] font-medium tracking-wide">Ranks</span>
          </button>
        </div>

      </div>
    </div>
  );
}