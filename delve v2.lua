local function notify(message, title)
	print("[" .. title .. "] " .. message);
end;

local function start()
notify("Starting…", "Delve Potassium");
local env = getgenv();
local missingInput;
do
	local required = {
		isrbxactive = isrbxactive, keypress = keypress, keyrelease = keyrelease,
		mousemoveabs = mousemoveabs, mouse1press = mouse1press, mouse1release = mouse1release,
	};
	for name in string.gmatch("isrbxactive keypress keyrelease mousemoveabs mouse1press mouse1release", "%S+") do
		if type(required[name]) ~= "function" then
			missingInput = "Missing Potassium function: " .. name;
			notify(missingInput, "Delve");
			break;
		end;
	end;
end;

local instanceIds = setmetatable({}, { __mode = "k" });
local nextId = 0;
local function instanceId(instance)
	local id = instanceIds[instance];
	if not id then
		nextId = nextId + 1;
		id = nextId;
		instanceIds[instance] = id;
	end;
	return id;
end;

local m = {
		on = false,
		mine = true,
		walk = false,
		radius = .69,
		reach = 1.29,
		combat = true,
		chase = true,
		fightDist = 8,
		autoCombatStats = true,
		dodge = true,
		autoRoll = true,
		chests = true,
		centerFarm = false,
		autoReplay = false,
		antiAfk = false,
		dodgeLog = false,
		replayDelay = 2.5,
		chestRange = 120,
		keepAway = 7,
		hitMargin = 1.5,
		meleeReach = 5.5,
		rollLead = .2,
		feat = {},
		cardPick = false,
		-- new settings
		mineRange = 150,
		autoStats = false,
		reachScale = 1,
		radiusScale = .85,
		centerOre = false,
		minTier = 1,
		skipAfter = 9,
		autoEquip = true,
		pickSlot = 1,
		weaponSlot = 2,
		rollKey = "Q",
		-- center farm / dodge fixes
		centerCleanup = true,
		rollCooldown = 1.05,
		pingComp = true,
		windupLearn = true,
		-- background / silent aim
		background = false,
		silentAim = false,
		bgKeyMethod = "Auto",
		bgMoveMethod = "Both",
		useLearned = true,
	};
local G = env.Delve;
if G and G.stop then
	pcall(G.stop);
end;
env.Delve = { cfg = (G and G.cfg) or m };
local r = env.Delve;
local Q = r.cfg;
for m, G in pairs(m) do
	if Q[m] == nil then
		Q[m] = G;
	end;
end;
Q.cardPick = false;
if not Q.bgMigrated then
	Q.bgMigrated = true;
	if Q.bgKeyMethod == "VirtualInputManager" then
		Q.bgKeyMethod = "Auto";
	end;
end;
local e = {
		"mine",
		"walk",
		"combat",
		"chase",
		"dodge",
		"autoRoll",
		"chests",
	};
local function N(m)
	Q.on = m and true or false;
	r.farmOn = Q.on;
	for m, G in ipairs(e) do
		Q[G] = Q.on and Q.feat[G] ~= false;
	end;
end;
N(false);
local S = game:GetService("Players") or game.Players;
local w = game:GetService("ReplicatedStorage") or game.ReplicatedStorage;
local q = game:GetService("RunService") or game.RunService;
local l = S.LocalPlayer;
if not l then
	notify("Join Delve before running the script.", "Delve");
	return;
end;
local guiService = game:GetService("GuiService");
local d = (type(os) == "table" and os.clock) or tick;
local function f(m)
	if Q.dodgeLog then
		pcall(appendfile, "dodge_log.txt", string.format("%.2f %s\n", d(), m));
	end;
end;
local z = 8;
local x = 67108864;
-- Input backends. Foreground mode uses the executor's OS-level input (needs Roblox focused).
-- Background mode avoids OS input entirely so the game can sit behind other windows:
--   walking     -> Humanoid:Move every physics step
--   keys        -> VirtualInputManager (or the game's own InputBegan/InputEnded connections)
--   mouse aim   -> silent aim: the mouse values the game reads are spoofed, the real cursor never moves
--   GUI buttons -> fired directly (replay button, relic cards)
local inp = {};
do
	local UIS = game:GetService("UserInputService");
	local VIM;
	pcall(function() VIM = game:GetService("VirtualInputManager"); end);
	-- shared with the metamethod hooks, which are installed once per executor session
	local shared = env.DelveAim;
	if type(shared) ~= "table" then
		shared = {};
		env.DelveAim = shared;
	end;
	shared.mouse = l:GetMouse();
	shared.uis = UIS;
	shared.inset = guiService:GetGuiInset();
	shared.world, shared.view = nil, nil;
	inp.moveVec = nil;
	inp.learned = type(env.DelveLearned) == "table" and env.DelveLearned or {};
	env.DelveLearned = inp.learned;
	inp.keyMode = {};

	local osKeypress, osKeyrelease, osMoveAbs = keypress, keyrelease, mousemoveabs;
	local osDown, osUp, osActive = mouse1press, mouse1release, isrbxactive;

	local digitNames = { [0] = "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" };
	local specialEnums = { [32] = "Space", [16] = "LeftShift", [160] = "LeftShift", [161] = "RightShift", [17] = "LeftControl", [18] = "LeftAlt", [9] = "Tab" };
	local function keyEnum(vk)
		local name = specialEnums[vk];
		if not name and vk >= 65 and vk <= 90 then name = string.char(vk); end;
		if not name and vk >= 48 and vk <= 57 then name = digitNames[vk - 48]; end;
		return name and Enum.KeyCode[name];
	end;

	function inp.active()
		if Q.background == true then return true; end;
		return type(osActive) == "function" and osActive() or false;
	end;
	function inp.focused()
		return type(osActive) == "function" and osActive() or false;
	end;
	function inp.silent()
		return (Q.silentAim == true or Q.background == true) and shared.hooked == true;
	end;

	-- keys ---------------------------------------------------------------
	local function viaConnections(code, down)
		if type(getconnections) ~= "function" then return false; end;
		local input = {
			KeyCode = code,
			UserInputType = Enum.UserInputType.Keyboard,
			UserInputState = down and Enum.UserInputState.Begin or Enum.UserInputState.End,
			Position = Vector3.zero,
			Delta = Vector3.zero,
			IsModifierKeyDown = function() return false; end,
		};
		local fired = false;
		for _, c in ipairs(getconnections(down and UIS.InputBegan or UIS.InputEnded)) do
			local fn = c.Function;
			if type(fn) == "function" then
				task.spawn(fn, input, false);
				fired = true;
			end;
		end;
		return fired;
	end;
	local function viaVim(code, down)
		return VIM ~= nil and (pcall(VIM.SendKeyEvent, VIM, down, code, false, game));
	end;
	local function sendKey(vk, down)
		local code = keyEnum(vk);
		if not code then return false; end;
		local method = Q.bgKeyMethod;
		if method == "Input connections" then
			return viaConnections(code, down);
		elseif method == "VirtualInputManager" then
			return viaVim(code, down) or viaConnections(code, down);
		end;
		-- Auto: VirtualInputManager only reaches the game while Roblox is focused, so when tabbed out use the
		-- game's own input connections. If a tool key stops having an effect, OQ rotates this key's method.
		if inp.focused() then
			return viaVim(code, down) or viaConnections(code, down);
		end;
		local mode = inp.keyMode[vk] or "connections";
		if mode == "vim" then
			return viaVim(code, down) or viaConnections(code, down);
		elseif mode == "both" then
			local a = viaConnections(code, down);
			local b = viaVim(code, down);
			return a or b;
		end;
		return viaConnections(code, down) or viaVim(code, down);
	end;
	local modeOrder = { "connections", "vim", "both" };
	function inp.rotateKey(vk)
		local current = inp.keyMode[vk] or "connections";
		local nextIndex = 1;
		for i, name in ipairs(modeOrder) do
			if name == current then nextIndex = i % #modeOrder + 1; end;
		end;
		inp.keyMode[vk] = modeOrder[nextIndex];
		return inp.keyMode[vk];
	end;
	function inp.key(vk, down)
		if Q.background == true then
			sendKey(vk, down);
		elseif down then
			if osKeypress then osKeypress(vk); end;
		else
			if osKeyrelease then osKeyrelease(vk); end;
		end;
	end;

	-- real mouse (foreground only) -------------------------------------------
	function inp.mouseMove(x, y) if osMoveAbs then osMoveAbs(x, y); end; end;
	function inp.mouseDown() if osDown then osDown(); end; end;
	function inp.mouseUp() if osUp then osUp(); end; end;

	-- GUI buttons ------------------------------------------------------------
	local function fireEvent(signal)
		if type(firesignal) == "function" and pcall(firesignal, signal) then
			return true;
		end;
		if type(getconnections) == "function" then
			local fired = false;
			for _, c in ipairs(getconnections(signal)) do
				if type(c.Fire) == "function" then
					pcall(c.Fire, c);
					fired = true;
				elseif type(c.Function) == "function" then
					task.spawn(c.Function);
					fired = true;
				end;
			end;
			return fired;
		end;
		return false;
	end;
	function inp.clickGui(button)
		if not button then return false; end;
		local target = button:IsA("GuiButton") and button or button:FindFirstChildWhichIsA("GuiButton", true);
		if not target then return false; end;
		return fireEvent(target.Activated) or fireEvent(target.MouseButton1Click);
	end;

	-- walking ----------------------------------------------------------------
	local function humanoid()
		local character = l.Character;
		return character and character:FindFirstChildOfClass("Humanoid"), character;
	end;
	function inp.setMove(x, z)
		inp.moveVec = Vector3.new(x, 0, z);
	end;
	function inp.clearMove()
		if inp.moveVec then
			inp.moveVec = nil;
			local h = humanoid();
			if h then pcall(h.Move, h, Vector3.zero, false); end;
		end;
	end;
	local function applyMove()
		local v = inp.moveVec;
		if not v or not (Q.background == true or inp.testing) then return; end;
		local h, character = humanoid();
		if not h then return; end;
		local method = Q.bgMoveMethod or "Both";
		if method ~= "Velocity" then
			h:Move(v, false);
		end;
		if method ~= "Humanoid:Move" then
			local root = character:FindFirstChild("HumanoidRootPart");
			if root then
				local vel = root.AssemblyLinearVelocity;
				root.AssemblyLinearVelocity = Vector3.new(v.X * h.WalkSpeed, vel.Y, v.Z * h.WalkSpeed);
			end;
		end;
	end;
	-- the default controls write Move(0) on RenderStepped, so ours is written at several points in the frame:
	-- after them on RenderStepped, before physics on Stepped, and again on Heartbeat
	pcall(function() q:UnbindFromRenderStep("DelveMove"); end);
	pcall(function() q:BindToRenderStep("DelveMove", 2000, applyMove); end);
	inp.moveConn = q.Stepped:Connect(applyMove);
	inp.moveConn2 = q.Heartbeat:Connect(applyMove);

	-- silent aim -------------------------------------------------------------
	function inp.setAim(world)
		local camera = workspace.CurrentCamera;
		if not camera then return false; end;
		local p = camera:WorldToViewportPoint(world);
		if p.Z <= 0 then
			shared.world, shared.view, shared.target = nil, nil, nil;
			return false;
		end;
		shared.world = world;
		shared.view = Vector2.new(p.X, p.Y);
		-- Mouse.Target: whatever the camera ray through the aim point hits first (mining may read this)
		local origin = camera.CFrame.Position;
		local delta = world - origin;
		local params = RaycastParams.new();
		params.FilterType = Enum.RaycastFilterType.Exclude;
		params.FilterDescendantsInstances = { l.Character };
		local result = workspace:Raycast(origin, delta.Unit * (delta.Magnitude + 25), params);
		shared.target = result and result.Instance or nil;
		return true;
	end;
	function inp.clearAim()
		shared.world, shared.view, shared.target = nil, nil, nil;
	end;
	local function installHooks()
		if shared.hooked and shared.hookVersion == 2 then return true; end;
		if type(hookmetamethod) ~= "function" or type(newcclosure) ~= "function"
			or type(checkcaller) ~= "function" or type(getnamecallmethod) ~= "function" then
			return shared.hooked == true;
		end;
		local ok = pcall(function()
			local oldIndex;
			oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
				local view = shared.view;
				if view and self == shared.mouse and not checkcaller() then
					if key == "Target" then
						if shared.target then return shared.target; end;
					elseif key == "Hit" then
						return CFrame.new(shared.world);
					elseif key == "X" then
						return view.X;
					elseif key == "Y" then
						return view.Y - shared.inset.Y;
					elseif key == "UnitRay" then
						local origin = workspace.CurrentCamera.CFrame.Position;
						return Ray.new(origin, (shared.world - origin).Unit);
					end;
				end;
				return oldIndex(self, key);
			end));
			local oldNamecall;
			oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local view = shared.view;
				if view and self == shared.uis and getnamecallmethod() == "GetMouseLocation" and not checkcaller() then
					return view;
				end;
				return oldNamecall(self, ...);
			end));
		end);
		if ok then
			shared.hooked = true;
			shared.hookVersion = 2;
		end;
		return shared.hooked == true;
	end;
	function inp.ensureSilent()
		if Q.background == true or Q.silentAim == true then
			if not installHooks() then
				notify("Silent aim needs hookmetamethod, newcclosure, checkcaller and getnamecallmethod. One is missing in this executor build, so the real mouse is used.", "Delve");
			end;
		end;
	end;

	-- learn the game's own equip remotes ---------------------------------------
	-- A key press can't reach every game script while tabbed out, so instead record which remotes the game
	-- fires when you swap tools by hand, then replay exactly those calls in background mode.
	local function installRecorder()
		if shared.recHooked then return true; end;
		if type(hookmetamethod) ~= "function" or type(newcclosure) ~= "function"
			or type(checkcaller) ~= "function" or type(getnamecallmethod) ~= "function" then
			return false;
		end;
		local ok = pcall(function()
			local old;
			old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local log = shared.remoteLog;
				if log then
					local method = getnamecallmethod();
					if (method == "FireServer" or method == "InvokeServer") and not checkcaller() then
						log[#log + 1] = { t = d(), remote = self, method = method, args = table.pack(...) };
						if #log > 600 then table.remove(log, 1); end;
					end;
				end;
				return old(self, ...);
			end));
		end);
		shared.recHooked = ok;
		return ok;
	end;

	function inp.learn(action, vk)
		if not installRecorder() then
			notify("Learning needs hookmetamethod, newcclosure, checkcaller and getnamecallmethod.", "Delve learn");
			return;
		end;
		local code = keyEnum(vk);
		if not code then return; end;
		shared.remoteLog = {};
		local finished = false;
		local conn;
		conn = UIS.InputBegan:Connect(function(input)
			if finished or input.KeyCode ~= code then return; end;
			finished = true;
			conn:Disconnect();
			local pressAt = d();
			task.delay(.4, function()
				local log = shared.remoteLog or {};
				shared.remoteLog = nil;
				-- remotes that fire constantly before the press are background traffic, not the swap
				local baseline = {};
				for _, call in ipairs(log) do
					if call.t < pressAt - .05 then
						baseline[call.remote] = (baseline[call.remote] or 0) + 1;
					end;
				end;
				local found = {};
				for _, call in ipairs(log) do
					if call.t >= pressAt - .02 and (baseline[call.remote] or 0) < 3 then
						found[#found + 1] = { remote = call.remote, method = call.method, args = call.args };
					end;
				end;
				if #found == 0 then
					notify("Learn '" .. action .. "': nothing fired besides constant background traffic. Try again with the OTHER tool out so the key really swaps.", "Delve learn");
					return;
				end;
				inp.learned[action] = found;
				local names = {};
				for _, call in ipairs(found) do
					names[#names + 1] = call.remote.Name;
				end;
				notify(string.format("Learned '%s': %d remote call%s (%s). Background mode now replays these instead of pressing the key.",
					action, #found, #found == 1 and "" or "s", table.concat(names, ", ")), "Delve learn");
			end);
		end);
		task.delay(10, function()
			if not finished then
				finished = true;
				conn:Disconnect();
				shared.remoteLog = nil;
				notify("Learn '" .. action .. "': no key press seen in 10 seconds. Roblox must be focused while you press it.", "Delve learn");
			end;
		end);
		notify(string.format("Learning '%s'. Click into Roblox and press that tool's key within 10 seconds (have the OTHER tool out first so it really swaps).", action), "Delve learn");
	end;

	function inp.replay(action)
		local list = inp.learned[action];
		if not list or not list[1] then return false; end;
		for _, call in ipairs(list) do
			local remote = call.remote;
			if remote and remote.Parent then
				local args = call.args;
				if call.method == "InvokeServer" then
					task.spawn(function() remote:InvokeServer(table.unpack(args, 1, args.n)); end);
				else
					pcall(function() remote:FireServer(table.unpack(args, 1, args.n)); end);
				end;
			end;
		end;
		return true;
	end;

	function inp.report()
		local function has(fn) return type(fn) == "function" and "yes" or "NO"; end;
		return string.format("hookmetamethod %s | newcclosure %s | checkcaller %s | getnamecallmethod %s | VirtualInputManager %s | getconnections %s | firesignal %s | hooks installed: %s",
			has(hookmetamethod), has(newcclosure), has(checkcaller), has(getnamecallmethod),
			VIM and "yes" or "NO", has(getconnections), has(firesignal), shared.hooked and "yes" or "no");
	end;

	function inp.status()
		local h, character = humanoid();
		return string.format("background=%s silent=%s hooks=%s aimSet=%s target=%s moveVec=%s MoveDirection=%.2f PickaxeOut=%s WeaponDrawn=%s keys=%s move=%s learned weapon/pickaxe=%d/%d",
			tostring(Q.background == true), tostring(inp.silent()), tostring(shared.hooked == true), tostring(shared.view ~= nil),
			tostring(shared.target and shared.target.Name), tostring(inp.moveVec ~= nil),
			h and h.MoveDirection.Magnitude or -1,
			tostring(character and character:GetAttribute("PickaxeOut")), tostring(character and character:GetAttribute("WeaponDrawn")),
			tostring(Q.bgKeyMethod), tostring(Q.bgMoveMethod or "Both"),
			#(inp.learned.weapon or {}), #(inp.learned.pickaxe or {}));
	end;

	-- sends a slot key with the background key method and reports whether the game reacted
	function inp.testEquip(vk, attribute, label)
		local character = l.Character;
		if not character then
			notify("No character yet.", "Delve test");
			return;
		end;
		local before = character:GetAttribute(attribute);
		sendKey(vk, true);
		task.wait(.08);
		sendKey(vk, false);
		task.wait(.7);
		local after = character:GetAttribute(attribute);
		local focused = type(osActive) == "function" and osActive();
		local connections = type(getconnections) == "function" and #getconnections(UIS.InputBegan) or -1;
		notify(string.format("%s: %s %s -> %s | key method %s | Roblox %s | %d InputBegan connections%s",
			label, attribute, tostring(before), tostring(after), tostring(Q.bgKeyMethod),
			focused and "focused" or "tabbed out", connections,
			before == after and " | NO CHANGE: the game did not react to the key" or ""), "Delve test");
	end;

	-- walks forward for one second with the background movement method and reports the distance
	function inp.testWalk()
		local h, character = humanoid();
		local root = character and character:FindFirstChild("HumanoidRootPart");
		local camera = workspace.CurrentCamera;
		if not (h and root and camera) then
			notify("No character or camera yet.", "Delve test");
			return;
		end;
		local look = camera.CFrame.LookVector;
		local flat = Vector3.new(look.X, 0, look.Z).Unit;
		local from = root.Position;
		inp.testing = true;
		inp.setMove(flat.X, flat.Z);
		task.wait(1);
		local moveDirection = h.MoveDirection.Magnitude;
		inp.clearMove();
		inp.testing = false;
		local moved = (root.Position - from) * Vector3.new(1, 0, 1);
		notify(string.format("Walk test: moved %.1f studs in 1s (WalkSpeed %.0f, MoveDirection %.2f, method %s)%s",
			moved.Magnitude, h.WalkSpeed, moveDirection, tostring(Q.bgMoveMethod or "Both"),
			moved.Magnitude < 1 and " | DID NOT MOVE" or ""), "Delve test");
	end;

	function inp.stop()
		pcall(function() q:UnbindFromRenderStep("DelveMove"); end);
		if inp.moveConn then
			inp.moveConn:Disconnect();
			inp.moveConn = nil;
		end;
		if inp.moveConn2 then
			inp.moveConn2:Disconnect();
			inp.moveConn2 = nil;
		end;
		inp.clearMove();
		inp.clearAim();
	end;
end;
-- INPUT-BACKENDS-END
local function farmBlocker()
	if missingInput and Q.background ~= true then return missingInput; end;
	if not w:FindFirstChild("StrataNet") and not workspace:FindFirstChild("StrataPlate") then
		return "Waiting for Delve. Join a run and try again.";
	end;
end;
local function W(m)
	local G, r = 0, nil;
	for m, Q in ipairs(m:GetDescendants()) do
		local e = Q.ClassName;
		if e == "Part" or e == "MeshPart" then
			G = G + 1;
			if not r then
				r = Q.Color;
			end;
		end;
	end;
	local Q = r and string.format("%d,%d,%d", math.floor(r.R + .5), math.floor(r.G + .5), math.floor(r.B + .5)) or "-";
	return G, Q;
end;
local K, o = {}, {};
local F = {};
do
	local m = w:FindFirstChild("Assets");
	local G = m and m:FindFirstChild("Rocks");
	if G then
		for m, G in ipairs(G:GetChildren()) do
			local r, Q = W(G);
			K[r .. (("|" .. Q))] = G.Name;
			if o[r] == nil then
				o[r] = G.Name;
			else
				o[r] = false;
			end;
		end;
	end;
	local r = m and m:FindFirstChild("Mobs");
	if r then
		for m, G in ipairs(r:GetChildren()) do
			F[G.Name] = true;
		end;
	end;
end;
local j = { DelveCursedRock = true, DelveSporeBloom = true };
local R = {
		DelveTimeCrystal = 25,
		DelveTreasureGeode = 25,
		DelveRelicFountain = 15,
		DelveBlastRock = 3,
	};
local function C(m)
	if j[m] then
		return -6;
	end;
	if R[m] then
		return R[m];
	end;
	local G = tonumber(m and m:match("(%d+)$"));
	if not G or G <= 1 then
		return 1;
	end;
	return G * G;
end;
local D = {};
local E = nil;
local a = nil;
local i, s, O = {}, nil, false;
local V = {};
local function orePart(ore)
	if ore:IsA("BasePart") then return ore; end;
	return ore:FindFirstChildWhichIsA("BasePart") or ore:FindFirstChildWhichIsA("BasePart", true);
end;
local function y(m)
	local G = 10;
	local Q = workspace:FindFirstChild("StrataPlate");
	if not Q then
		if E then
			D, E, a = {}, nil, nil;
		end;
		return false;
	end;
	local e = instanceId(Q);
	if e ~= E then
		D, E, a, r.lastAim = {}, e, nil, nil;
		s, i, O, V = nil, {}, true, {};
		r.groundTileCount = nil;
		r.centerFarmTiles, r.centerFarmTile, r.centerFarmChest = nil, nil, nil;
		r.statsFound = false;
	end;
	local N = Q:FindFirstChild("Ground");
	local S = N and N:GetChildren();
	local w = S and ((S[1] and instanceId(S[1])));
	local tileCount = S and #S or 0;
	if w ~= s or tileCount ~= r.groundTileCount then
		s, i, O, V = w, {}, true, {};
		r.groundTileCount = tileCount;
		for m, G in ipairs(S or {}) do
			local r, Q = G.Name:match("^Tile_(%d+)_(%d+)$");
			if r then
				local m = G.Position;
				r, Q = tonumber(r), tonumber(Q);
				i[#i + 1] = {
						cx = r,
						cz = Q,
						wx = m.X,
						wz = m.Z,
						wy = m.Y,
					};
				V[r * 4096 + Q] = true;
			end;
		end;
	end;
	local q = {};
	for Q, e in ipairs(Q:GetChildren()) do
		local N = e.Name;
		local S = tonumber(N);
		if S then
			q[N] = true;
			local Q = instanceId(e);
			local w = D[N];
			if w and w.addr ~= Q then
				D[N] = nil;
				r.lastAim = nil;
				if #i < 3 then
					a = nil;
				end;
			end;
			if not D[N] then
				local part = orePart(e);
				if part then
					local G = part.Position;
					local r, w;
					if S >= x then
						local m = S - x;
						r = math.floor(m / 1024);
						w = ((m - r * 1024)) + .5;
						r = r + .5;
					else
						r = math.floor(S / 1024);
						w = S - r * 1024;
					end;
					local q, l = W(e);
					local d = K[q .. (("|" .. l))] or o[q] or "?";
					D[N] = {
							cx = r,
							cz = w,
							wx = G.X,
							wy = G.Y,
							wz = G.Z,
							kind = d,
							addr = Q,
							instance = e,
						};
				end;
			else
				local r = D[N];
				local Q = not r.settled or (G > 0 and m - ((r.readAt or 0)) > 3);
				if Q then
					if r.settled then
						G = G - 1;
					end;
					local part = orePart(e);
					local N = part and part.Position;
					if not N then
						D[e.Name] = nil;
					else
						r.readAt = m;
						if math.abs(N.Y - r.wy) < .05 and ((math.abs(N.X - r.wx) < .05 and math.abs(N.Z - r.wz) < .05)) then
							r.stillSince = r.stillSince or m;
							if m - r.stillSince >= 1.5 then
								r.settled = true;
							end;
						else
							r.stillSince, r.settled = nil, false;
							if #i < 3 then
								a = nil;
							end;
						end;
						r.wx, r.wy, r.wz = N.X, N.Y, N.Z;
					end;
				end;
			end;
		end;
	end;
	for m in pairs(D) do
		if not q[m] then
			D[m] = nil;
		end;
	end;
	return true;
end;
r.debugRocks = function()
		local m, G = 0, nil;
		for r, Q in pairs(D) do
			m = m + 1;
			G = G or string.format("%s@%.0f,%.0f,%.0f", r, Q.wx, Q.wy, Q.wz);
		end;
		return m, G, E, a ~= nil;
	end;
local function b(m, G)
	local r = ((m[1] * ((m[5] * m[9] - m[6] * m[8])) - m[2] * ((m[4] * m[9] - m[6] * m[7])))) + m[3] * ((m[4] * m[8] - m[5] * m[7]));
	if math.abs(r) < 1e-09 then
		return nil;
	end;
	local function Q(m, G, r)
		return ((m[1] * ((G[2] * r[3] - G[3] * r[2])) - G[1] * ((m[2] * r[3] - m[3] * r[2])))) + r[1] * ((m[2] * G[3] - m[3] * G[2]));
	end;
	local e, N, S = { m[1], m[4], m[7] }, { m[2], m[5], m[8] }, { m[3], m[6], m[9] };
	return { Q(G, N, S) / r, Q(e, G, S) / r, Q(e, N, G) / r };
end;
local function v(m, G, r, Q)
	local e = {
			0,
			0,
			0,
			0,
			0,
			0,
			0,
			0,
			0,
		};
	local N = { 0, 0, 0 };
	for m, S in ipairs(m) do
		local w, q, l = S[G], S[r], S[Q];
		e[1] = e[1] + w * w;
		e[2] = e[2] + w * q;
		e[3] = e[3] + w;
		e[5] = e[5] + q * q;
		e[6] = e[6] + q;
		e[9] = e[9] + 1;
		N[1] = N[1] + w * l;
		N[2] = N[2] + q * l;
		N[3] = N[3] + l;
	end;
	e[4], e[7], e[8] = e[2], e[3], e[6];
	return b(e, N);
end;
local function n(m)
	if #i >= 3 then
		if O or not a then
			O = false;
			local m, G = v(i, "wx", "wz", "cx"), v(i, "wx", "wz", "cz");
			local r, Q = v(i, "cx", "cz", "wx"), v(i, "cx", "cz", "wz");
			if m and ((G and ((r and Q)))) then
				return {
					toCx = m,
					toCz = G,
					toWx = r,
					toWz = Q,
					y = i[1].wy + 1.8,
				};
			end;
		else
			return a;
		end;
	end;
	if #m < 3 then
		return a;
	end;
	local G = v(m, "wx", "wz", "cx");
	local r = v(m, "wx", "wz", "cz");
	local Q = v(m, "cx", "cz", "wx");
	local e = v(m, "cx", "cz", "wz");
	if not ((G and ((r and ((Q and e)))))) then
		return a;
	end;
	local N = 0;
	for m, G in ipairs(m) do
		N = N + G.wy;
	end;
	return {
		toCx = G,
		toCz = r,
		toWx = Q,
		toWz = e,
		y = N / #m,
	};
end;
local function g(m, G, r)
	return ((m.toCx[1] * G + m.toCx[2] * r)) + m.toCx[3], ((m.toCz[1] * G + m.toCz[2] * r)) + m.toCz[3];
end;
local function Z(m, G, r)
	return Vector3.new(((m.toWx[1] * G + m.toWx[2] * r)) + m.toWx[3], m.y, ((m.toWz[1] * G + m.toWz[2] * r)) + m.toWz[3]);
end;
local k, T, A, h, U = .707, -0.707, -0.707, -0.707, .91;
local function B()
	local m = workspace.CurrentCamera;
	if not m then
		return;
	end;
	local G = m.CFrame;
	local r, Q = G.RightVector, G.LookVector;
	local e = math.sqrt(r.X * r.X + r.Z * r.Z);
	local N = math.sqrt(Q.X * Q.X + Q.Z * Q.Z);
	if e < .001 or N < .001 then
		return;
	end;
	k, T, A, h = r.X / e, r.Z / e, Q.X / N, Q.Z / N;
	U = math.max(.2, math.min(1, -Q.Y));
end;
local function M(m, G)
	local r = m * k + G * T;
	local Q = ((m * A + G * h)) * U;
	return math.sqrt(r * r + Q * Q);
end;
local L = nil;
local X = nil;
local u = nil;
local Y = 0;
local function p(m, G, r, Q, e)
	local N = M(r - m, Q - G);
	if N <= e or N < 1e-06 then
		return r, Q;
	end;
	local S = e / N;
	return m + ((r - m)) * S, G + ((Q - G)) * S;
end;
local function H(m)
	local G = {};
	for m, r in ipairs(m) do
		local Q = math.floor(r.cx) * 4096 + math.floor(r.cz);
		local e = G[Q];
		if not e then
			e = {};
			G[Q] = e;
		end;
		e[#e + 1] = r;
	end;
	return G;
end;
-- Mining coverage uses grid distance. Camera pitch only affects aim reach.
local function miningDistanceSquared(dx, dz)
	return dx * dx + dz * dz;
end;
local function t(m, G, r, Q)
	local e, N = 0, 0;
	local S = math.ceil(Q) + 1;
	local radiusSquared = Q * Q;
	local w, q = math.floor(G), math.floor(r);
	for w = w - S, w + S, 1 do
		for S = q - S, q + S, 1 do
			local q = m[w * 4096 + S];
			if q then
				for m, S in ipairs(q) do
					if miningDistanceSquared(S.cx - G, S.cz - r) <= radiusSquared then
						e = e + S.w;
						if S.w > 0 then
							N = N + 1;
						end;
					end;
				end;
			end;
		end;
	end;
	return e, N;
end;
local function P(m, G, r, Q)
	local e = {};
	local N = math.ceil(2 * r);
	for m, S in ipairs(m) do
		if S.w > 0 then
			e[#e + 1] = { S.cx, S.cz, S.instance };
			if Q then
				for m = -0.5, .5, 1 do
					for G = -0.5, .5, 1 do
						e[#e + 1] = { S.cx + m, S.cz + G };
					end;
				end;
				local m, Q = math.floor(S.cx), math.floor(S.cz);
				for m = m - N, m + N, 1 do
					for Q = Q - N, Q + N, 1 do
						local N = G[m * 4096 + Q];
						if N then
							for m, G in ipairs(N) do
								if G.w > 0 and ((((G.cx > S.cx or (G.cx == S.cx and G.cz > S.cz))) and miningDistanceSquared(G.cx - S.cx, G.cz - S.cz) <= 4 * r * r)) then
									e[#e + 1] = { ((S.cx + G.cx)) / 2, ((S.cz + G.cz)) / 2 };
								end;
							end;
						end;
					end;
				end;
			end;
		end;
	end;
	return e;
end;
local J = {};
local function I(m, G, r, Q, e)
	local N = {};
	for m, S in ipairs(m) do
		local w, q = t(G, S[1], S[2], r);
		if q > 0 and w > 0 then
			N[#N + 1] = {
					ax = S[1],
					az = S[2],
					score = w,
					v = w / ((1 + .04 * M(S[1] - Q, S[2] - e))),
				};
		end;
	end;
	table.sort(N, function(m, G)
		return m.v > G.v;
	end);
	local S = {};
	for m, G in ipairs(N) do
		local Q = true;
		for m, e in ipairs(S) do
			if M(G.ax - e.ax, G.az - e.az) < r * 1.5 then
				Q = false;
				break;
			end;
		end;
		if Q then
			S[#S + 1] = G;
			if #S >= 60 then
				break;
			end;
		end;
	end;
	return S;
end;
local function ml(m, G, r, Q)
	local e, N = {}, {};
	local S, w = G, r;
	if Q then
		e[1], N[Q] = Q, true;
		S, w = m[Q].ax, m[Q].az;
	end;
	while #e < #m do
		local G, r = nil, nil;
		for m, Q in ipairs(m) do
			if not N[m] then
				local e = M(Q.ax - S, Q.az - w);
				if not r or e < r then
					G, r = m, e;
				end;
			end;
		end;
		N[G] = true;
		e[#e + 1] = G;
		S, w = m[G].ax, m[G].az;
	end;
	return e;
end;
local function Gl(m, G, r, Q, e)
	local function N(e)
		if e == 0 then
			return r, Q;
		end;
		local N = m[G[e]];
		return N.ax, N.az;
	end;
	local function S(m, G)
		local r, Q = N(m);
		local e, S = N(G);
		return M(r - e, Q - S);
	end;
	local w = #G;
	local q, l = true, 0;
	while q and l < 20 do
		q, l = false, l + 1;
		for m = e and 2 or 1, w - 1, 1 do
			for r = m + 1, w, 1 do
				local Q = S(m - 1, m) + ((r < w and S(r, r + 1) or 0));
				local e = S(m - 1, r) + ((r < w and S(m, r + 1) or 0));
				if e < Q - 1e-06 then
					local Q, e = m, r;
					while Q < e do
						G[Q], G[e] = G[e], G[Q];
						Q, e = Q + 1, e - 1;
					end;
					q = true;
				end;
			end;
		end;
	end;
	return G;
end;
local function rl(m, G, r, Q)
	local e, N, S = 0, r, Q;
	for G, r in ipairs(G) do
		local Q = m[r];
		e = e + M(Q.ax - N, Q.az - S);
		N, S = Q.ax, Q.az;
	end;
	return e;
end;
local function cQ(m)
	local camera = workspace.CurrentCamera;
	if not camera then return nil; end;
	local G, r = camera:WorldToScreenPoint(m);
	if (not r or (G.X == 0 and G.Y == 0)) and not (inp.silent() and G.Z > 0) then
		return nil;
	end;
	return G;
end;
local function Ql(m, G)
	L, u = nil, nil;
	local e = {};
	-- rock search range (0 = unlimited) and minimum tier filter
	local rng = tonumber(Q.mineRange) or 0;
	local rngSq = rng > 0 and rng * rng or nil;
	local minTier = tonumber(Q.minTier) or 1;
	for pass = 1, 2 do
		local hasTarget = false;
		for rockName, r in pairs(D) do
			local Q = r.wy - m.Y;
			if (math.abs(Q) < 6 or (Q >= 6 and (Q < 40 and not r.settled))) and (pass == 2 or not rngSq or (r.wx - m.X) ^ 2 + (r.wz - m.Z) ^ 2 <= rngSq) then
				r.name = rockName;
				local wt = (r.skipUntil and r.skipUntil > G) and 0 or C(r.kind);
				if wt > 0 and minTier > 1 then
					local tn = tonumber(tostring(r.kind):match("(%d+)$"));
					if tn and tn < minTier then
						wt = 0;
					end;
				end;
				r.w = wt;
				hasTarget = hasTarget or wt > 0;
				e[#e + 1] = r;
			end;
		end;
		-- nothing in range: if walking is on, widen the search so we walk to the nearest rocks
		if hasTarget or not Q.walk or not rngSq or pass == 2 then
			break;
		end;
		e = {};
	end;
	a = n(e);
	r.rockCount = #e;
	if not r.prevCount or #e < r.prevCount or #e > r.prevCount + 2 then
		r.progressAt = G;
	end;
	r.prevCount = #e;
	if not a or #e == 0 then
		X = nil;
		r.posCount, r.noAimSince = 0, nil;
		return;
	end;
	local N, S = g(a, m.X, m.Z);
	r.cell = { N, S };
	-- center farm: if nothing could be aimed for a moment, drop the safety margins so ores
	-- sitting right at the edge of the mining circle still get hit
	local relax = Q.centerFarm and r.noAimSince and G - r.noAimSince > .4;
	local w = math.max(.3, (tonumber(Q.reach) or 1.29) * (tonumber(Q.reachScale) or 1)) * (relax and 1 or .95);
	local miningRadius = math.max(.1, tonumber(Q.radius) or .69);
	local radiusScale = relax and .97 or math.max(.4, math.min(1, tonumber(Q.radiusScale) or .85));
	local q = miningRadius * radiusScale;
	r.relaxed = relax and true or false;
	local l = H(e);
	local d = 0;
	for m, G in ipairs(e) do
		if G.w > 0 then
			d = d + 1;
		end;
	end;
	local centerOre = Q.centerOre == true;
	local f = not centerOre and (d >= 5 or (Q.centerFarm and d >= 2));
	if r.clusterOn ~= f or r.centerOre ~= centerOre then
		X = nil;
	end;
	r.clusterOn = f;
	r.centerOre = centerOre;
	local z = {};
	for m, G in ipairs(e) do
		if M(G.cx - N, G.cz - S) <= ((w + q)) + .5 then
			z[#z + 1] = G;
		end;
	end;
	local x = nil;
	local bestCenterDistance = math.huge;
	local retryDirect = Q.centerFarm and G - (r.progressAt or G) >= 2;
	local preferDirect = centerOre or retryDirect;
	for pass = 1, (Q.centerFarm and 2 or 1) do
		local direct = (pass == 1 and preferDirect) or (pass == 2 and not preferDirect);
		local cluster = not direct and (f or (Q.centerFarm and d >= 2));
		for _, candidate in ipairs(P(z, l, q, cluster)) do
			local aimX, aimZ = candidate[1], candidate[2];
			local inReach = M(aimX - N, aimZ - S) <= w;
			if not direct then
				aimX, aimZ = p(N, S, aimX, aimZ, w);
				inReach = true;
			end;
			local score, hits = 0, 0;
			local ore = direct and candidate[3] or nil;
			if inReach and Q.centerFarm then
				local part = ore and orePart(ore);
				local point = not direct and Z(a, aimX, aimZ) or (part and part.Position);
				inReach = point and cQ(point);
			end;
			if inReach then score, hits = t(l, aimX, aimZ, q); end;
			if hits > 0 and score > 0 and (not x or score >= x.score - 1e-6) then
				local centerDistance = math.huge;
				for _, rock in ipairs(z) do
					if rock.w > 0 then
						centerDistance = math.min(centerDistance, miningDistanceSquared(rock.cx - aimX, rock.cz - aimZ));
					end;
				end;
				local aimDistance = M(aimX - N, aimZ - S);
				if not x or score > x.score + 1e-6
					or centerDistance < bestCenterDistance - 1e-6
					or (math.abs(centerDistance - bestCenterDistance) <= 1e-6 and aimDistance < x.d)
				then
					x = { ax = aimX, az = aimZ, score = score, n = hits, d = aimDistance, ore = ore };
					bestCenterDistance = centerDistance;
				end;
			end;
		end;
		if x then break; end;
	end;
	L = x;
	r.lastAim = x;
	-- remember whether ores exist that we currently can't aim at (drives the center-farm stray trip)
	r.posCount = d;
	if x then
		r.noAimSince = nil;
	elseif d > 0 then
		r.noAimSince = r.noAimSince or G;
	else
		r.noAimSince = nil;
	end;
	if X then
		X.score = t(l, X.ax, X.az, q);
		if X.score <= 0 then
			X = nil;
		end;
	end;
	if not X or G - Y >= .5 then
		Y = G;
		local m = I(P(e, l, q, f), l, q, N, S);
		if #J > 0 and a then
			local G = {};
			for m, r in ipairs(m) do
				local Q = Z(a, r.ax, r.az);
				local e = false;
				for m, G in ipairs(J) do
					if ((Q.X - G.x)) ^ 2 + ((Q.Z - G.z)) ^ 2 < G.block * G.block then
						e = true;
						break;
					end;
				end;
				if not e then
					G[#G + 1] = r;
				end;
			end;
			m = G;
		end;
		if #m > 0 then
			local G = Gl(m, ml(m, N, S), N, S);
			local r = rl(m, G, N, S);
			local Q = m[G[1]];
			local e = nil;
			if X then
				for G, r in ipairs(m) do
					if M(r.ax - X.ax, r.az - X.az) < q then
						e = rl(m, Gl(m, ml(m, N, S, G), N, S, true), N, S);
						break;
					end;
				end;
			end;
			if not X or not e or r < e * .9 then
				X = {
						ax = Q.ax,
						az = Q.az,
						score = Q.score,
						v = r,
					};
			end;
		end;
	end;
	r.walkGoal = X;
	if not x then
		r.progressAt = G;
	end;
	local K = G - ((r.progressAt or G));
	if K > (tonumber(Q.skipAfter) or 9) and x then
		local stalledRock;
		local closest = math.huge;
		for _, rock in ipairs(e) do
			if rock.w > 0 then
				local distance = miningDistanceSquared(rock.cx - x.ax, rock.cz - x.az);
				if distance <= q * q and distance < closest then
					stalledRock, closest = rock, distance;
				end;
			end;
		end;
		if stalledRock then
			stalledRock.skipUntil = G + 3;
			r.skipped = (r.skipped or 0) + 1;
		end;
		r.progressAt, r.lastAim, r.walkGoal = G, nil, nil;
		L, X, u = nil, nil, nil;
		K = 0;
	end;
	r.stalled = K > 4;
	if X then
		local m = M(X.ax - N, X.az - S);
		if (not x and m > .01) or (r.stalled and m > .35) or (x and m > w * .85 and X.score > x.score * 1.2) then
			u = Z(a, X.ax, X.az);
		end;
	end;
end;
local el = {};
local Nl = nil;
local function Sl(m, G, r, Q)
	local e = G:FindFirstChild("Torso") or G:FindFirstChild("HumanoidRootPart") or G:FindFirstChild("Head");
	local N = e and e.Position;
	if typeof(N) ~= "Vector3" then
		return;
	end;
	if m.t and r - m.t > .001 then
		local G = r - m.t;
		local Q, e = ((N.X - m.x)) / G, ((N.Z - m.z)) / G;
		if math.abs(Q) > 80 or math.abs(e) > 80 then
			Q, e = 0, 0;
		end;
		m.vx = ((m.vx or 0)) * .5 + Q * .5;
		m.vz = ((m.vz or 0)) * .5 + e * .5;
	end;
	m.x, m.y, m.z, m.t = N.X, N.Y, N.Z, r;
	local S = G:GetAttribute("AtkPhase");
	if S ~= m.phase then
		if S == "windup" then
			m.windupAt = r;
		elseif S == "strike" then
			m.strikeAt = r;
			-- learn how long this mob's windup lasts so the roll can be scheduled before the strike lands
			local dv = env.Delve;
			if dv and m.windupAt and m.name then
				local dur = r - m.windupAt;
				if dur > .05 and dur < 4 then
					dv.windups = dv.windups or {};
					local old = dv.windups[m.name];
					dv.windups[m.name] = old and (old * .6 + dur * .4) or dur;
				end;
			end;
		end;
	end;
	m.phase = S;
	if Q or not m.hpT or r - m.hpT > .25 then
		m.hpT = r;
		local Q = G:FindFirstChildOfClass("Humanoid");
		if Q then
			m.hp, m.max = Q.Health, Q.MaxHealth;
		end;
	end;
end;
local function wl(m, G, r)
	m.chk = r;
	if G:GetAttribute("MobId") == nil then
		m.owned = false;
		m.pending = true;
		return;
	end;
	m.pending = nil;
	local Q = G:GetAttribute("Owner");
	if Q ~= nil then
		m.owned = Q == l.UserId;
	else
		local r = G:GetAttribute("RunId");
		m.owned = r == nil or r == Nl;
	end;
end;
local ql = {};
local ll = {};
local dl = Q.chestRange;
local function fl(m, G)
	local r = m:FindFirstChild("Body") or m:FindFirstChild("Base") or m.PrimaryPart;
	local Q = r and r.Position;
	if typeof(Q) ~= "Vector3" then
		return nil;
	end;
	if G and ((Q.X - G.X)) ^ 2 + ((Q.Z - G.Z)) ^ 2 > dl * dl then
		return nil;
	end;
	local e = instanceId(m);
	local N = ll[e];
	if N == nil then
		local G = m:GetAttribute("Viewer");
		local r = m:GetAttribute("Owner");
		N = ((G == nil or G == l.UserId)) and ((((r == nil or r == l.UserId)) and not m:GetAttribute("HiddenFor_" .. l.UserId)));
		ll[e] = N;
	end;
	if not N then
		return nil;
	end;
	local S = m:GetAttribute("ChestState");
	if S == "open" then
		return nil;
	end;
	return e, {
		x = Q.X,
		z = Q.Z,
		locked = S ~= "unlocked",
		state = S,
	};
end;
local function zl(m)
	Nl = l:GetAttribute("RunId");
	local G = workspace:GetChildren();
	local r = {};
	local e = l.Character;
	local N = e and e:FindFirstChild("HumanoidRootPart");
	local S = N and N.Position;
	local w = {};
	for G, e in ipairs(G) do
		local N = e.Name;
		if (Q.chests or (Q.on and Q.centerFarm)) and (not F[N] and ((N == "DelveChest" or (e.ClassName == "Model" and e:GetAttribute("ChestRarity") ~= nil)))) then
			local m, G = fl(e, S);
			if m then
				w[m] = G;
			end;
		elseif F[N] then
			local Q = instanceId(e);
			r[Q] = true;
			local N = el[Q];
			if not N then
				N = { name = e.Name };
				el[Q] = N;
			end;
			N.idx = G;
			if N.owned == nil or (not N.owned and m - N.chk > ((N.pending and .4 or 2))) then
				wl(N, e, m);
			end;
			if N.owned then
				Sl(N, e, m);
			end;
		end;
	end;
	for m in pairs(el) do
		if not r[m] then
			el[m] = nil;
		end;
	end;
	ql = w;
	local plate = workspace:FindFirstChild("StrataPlate");
	r.chestScanPlate = plate and instanceId(plate);
end;
local function cl(m)
	local G, r = nil, nil;
	for Q, e in pairs(ql) do
		if not e.locked then
			local Q = ((e.x - m.X)) ^ 2 + ((e.z - m.Z)) ^ 2;
			if not r or Q < r then
				G, r = e, Q;
			end;
		end;
	end;
	return G;
end;
local function xl(m)
	local G = nil;
	for r, Q in pairs(el) do
		if Q.owned then
			G = G or workspace:GetChildren();
			local e = G[Q.idx];
			if not e or instanceId(e) ~= r then
				e = nil;
				for m = math.max(1, Q.idx - 12), math.min(#G, Q.idx + 12), 1 do
					local N = G[m];
					if instanceId(N) == r then
						e, Q.idx = N, m;
						break;
					end;
				end;
			end;
			if e then
				Sl(Q, e, m);
			else
				el[r] = nil;
			end;
		end;
	end;
end;
local function Wl(m, G, r)
	local Q = workspace:GetChildren();
	local e = Q[G.idx];
	if e and instanceId(e) == m then
		G.dead = e:GetAttribute("Dead") and true or false;
	end;
end;
local function Kl(m, G)
	local r = math.min(.15, G - ((m.t or G)));
	return Vector3.new(m.x + ((m.vx or 0)) * r, m.y, m.z + ((m.vz or 0)) * r);
end;
local function ol()
	local m = {};
	for G, r in pairs(el) do
		if r.owned and ((r.x and ((not r.dead and ((r.hp == nil or r.hp > 0)))))) then
			r.addr = G;
			m[#m + 1] = r;
		end;
	end;
	return m;
end;
local Fl = {};
local jl = { "Hazards", "MobTelegraphs", "DelveHazards" };
local function Rl(m)
	local G = math.sqrt(m.X * m.X + m.Z * m.Z);
	if G < .001 then
		return 0, 0;
	end;
	return m.X / G, m.Z / G;
end;
local Cl = {};
local function Dl(m)
	return m > .05 and m < .065;
end;
local function El(m, G)
	local r = { { v = m.RightVector, s = G.X }, { v = m.UpVector, s = G.Y }, { v = m.LookVector, s = G.Z } };
	local Q, e = 1, -1;
	for m, G in ipairs(r) do
		local r = math.abs(G.v.Y);
		if r > e then
			Q, e = m, r;
		end;
	end;
	local N = r[Q].s;
	table.remove(r, Q);
	local S, w = Rl(r[1].v);
	local q, l = Rl(r[2].v);
	local d, f = r[1].s / 2, r[2].s / 2;
	local z = m.Position;
	return {
		x = z.X,
		z = z.Z,
		ax = S,
		az = w,
		bx = q,
		bz = l,
		h1 = d,
		h2 = f,
		circle = math.abs(d - f) <= .06 * math.max(d, f),
	}, N;
end;
local function al(m, G)
	for m, G in pairs(Cl) do
		G.seen = false;
	end;
	local function r(m, G)
		if m.circle and G.circle then
			if ((m.x - G.x)) ^ 2 + ((m.z - G.z)) ^ 2 < .01 and G.h1 < m.h1 - .01 then
				return G.h1 / m.h1;
			end;
		elseif not m.circle and ((not G.circle and ((math.abs(m.h1 - G.h1) < .05 and ((m.bx * G.bx + m.bz * G.bz > .99 and G.h2 < m.h2 - .01)))))) then
			local r, Q = m.x - m.bx * m.h2, m.z - m.bz * m.h2;
			local e, N = G.x - G.bx * G.h2, G.z - G.bz * G.h2;
			if ((r - e)) ^ 2 + ((Q - N)) ^ 2 < .04 then
				return G.h2 / m.h2;
			end;
		end;
		return nil;
	end;
	for Q, e in ipairs(m) do
		local N, S, w = nil, 0, false;
		for m, G in ipairs(m) do
			if Q ~= m then
				local m = r(e, G);
				if m then
					N, S = m, S + 1;
				elseif r(G, e) then
					w = true;
				end;
			end;
		end;
		if S == 1 and not w then
			local m = string.format("%d:%d:%d", math.floor(e.x * 4 + .5), math.floor(e.z * 4 + .5), math.floor(((e.h1 + e.h2)) * 4 + .5));
			local r = Cl[m];
			if not r or N < r.p - .05 then
				r = { p0 = N, t0 = G };
				Cl[m] = r;
			end;
			r.zone, r.p, r.seen = e, N, true;
			if G - r.t0 > .03 and N > r.p0 + .01 then
				r.hitAt = r.t0 + ((((1 - r.p0)) * ((G - r.t0)))) / ((N - r.p0));
			end;
		end;
	end;
	for m, r in pairs(Cl) do
		if not r.seen and G - ((r.hitAt or r.t0)) > .3 then
			Cl[m] = nil;
		end;
	end;
end;
local il = .6;
local sl = 20;
local Ol = 1.5;
local Vl = Q.hitMargin;
local yl = 1.05;
local bl = Q.rollLead;
local vl = Q.meleeReach;
local nl = {};
local function gl(m, G, r, Q)
	local e = math.max(r / 2, .6);
	-- velocity is sampled over >= 40 ms and cached, so scanning every frame doesn't zero it out
	local N = nl[m];
	if not N or Q - N.t > .5 then
		N = { x = G.X, z = G.Z, t = Q };
		nl[m] = N;
	elseif Q - N.t >= .04 then
		local dt = Q - N.t;
		N.vx, N.vz = (G.X - N.x) / dt, (G.Z - N.z) / dt;
		N.x, N.z, N.t = G.X, G.Z, Q;
	end;
	if N.vx then
		local r2, S = N.vx, N.vz;
		local w = math.sqrt(r2 * r2 + S * S);
		if w > 2 then
			local m2, Q2 = r2 / w, S / w;
			local N2 = math.min(w * il, sl);
			return {
				x = G.X + (m2 * N2) / 2,
				z = G.Z + (Q2 * N2) / 2,
				ax = m2,
				az = Q2,
				bx = -Q2,
				bz = m2,
				h1 = N2 / 2 + e,
				h2 = e,
				circle = false,
				pm = Ol,
			}, m2, Q2, w;
		end;
	end;
	return {
		x = G.X,
		z = G.Z,
		ax = 1,
		az = 0,
		bx = 0,
		bz = 1,
		h1 = e,
		h2 = e,
		circle = true,
		pm = Ol,
	};
end;
local Zl = .4;
local kl = 20;
local Tl = {};
local function Al(m, G, r, Q, e, N)
	local S = m.x * m.ax + m.z * m.az;
	local w = m.x * m.bx + m.z * m.bz;
	local q, l = m.x + G * N, m.z + r * N;
	local d = q * m.ax + l * m.az;
	local f = q * m.bx + l * m.bz;
	local z = m.h1 + math.max(Q, 0) * N;
	local c = m.h2 + math.max(e, 0) * N;
	local x, W = math.min(S - m.h1, d - z), math.max(S + m.h1, d + z);
	local K, o = math.min(w - m.h2, f - c), math.max(w + m.h2, f + c);
	local F, j = ((x + W)) / 2, ((K + o)) / 2;
	return {
		x = F * m.ax + j * m.bx,
		z = F * m.az + j * m.bz,
		ax = m.ax,
		az = m.az,
		bx = m.bx,
		bz = m.bz,
		h1 = math.min(((W - x)) / 2, m.h1 + kl),
		h2 = math.min(((o - K)) / 2, m.h2 + kl),
		circle = false,
	};
end;
local function hl(m, G, r, Q)
	local e, N = G - m.x, r - m.z;
	return math.abs(e * m.ax + N * m.az) < m.h1 + Q and math.abs(e * m.bx + N * m.bz) < m.h2 + Q;
end;
local function Ul(m, G, r)
	-- growth/velocity is sampled over >= 40 ms and cached (same reason as gl)
	local Q = Tl[m];
	if not Q or r - Q.t > .5 then
		Tl[m] = { x = G.x, z = G.z, h1 = G.h1, h2 = G.h2, t = r };
		return G;
	end;
	local e = r - Q.t;
	if e >= .04 then
		Q.gh1, Q.gh2 = (G.h1 - Q.h1) / e, (G.h2 - Q.h2) / e;
		Q.gx, Q.gz = (G.x - Q.x) / e, (G.z - Q.z) / e;
		Q.x, Q.z, Q.h1, Q.h2, Q.t = G.x, G.z, G.h1, G.h2, r;
	end;
	if G.circle or not Q.gh1 then
		return G;
	end;
	local N, S, w, q = Q.gh1, Q.gh2, Q.gx, Q.gz;
	if N < 1 and (S < 1 and w * w + q * q < 1) then
		return G;
	end;
	return Al(G, w, q, N, S, Zl), w, q, N, S;
end;
local Bl, Ml = {}, -1000000000.0;
local function Ll(m)
	if m - Ml < .1 then
		return Bl;
	end;
	Ml = m;
	Bl = {};
	local G = workspace:FindFirstChild("Plates");
	if G then
		for m, G in ipairs(G:GetChildren()) do
			for m, G in ipairs(G:GetChildren()) do
				if G.Name:sub(1, 7) == "Hazard_" then
					Bl[#Bl + 1] = G;
				end;
			end;
		end;
	end;
	return Bl;
end;
local function Xl(m, G)
	Fl = {};
	local e = G or d();
	local N = {};
	local S = {};
	local function w(G)
		local r, Q = pcall(function()
				return G.Size;
			end);
		if not ((r and typeof(Q) == "Vector3")) then
			return;
		end;
		local w = G.CFrame;
		local q = w.Position;
		if m and ((q.X - m.X)) ^ 2 + ((q.Z - m.Z)) ^ 2 >= 3600 then
			return;
		end;
		local l = math.max(Q.X, Q.Y, Q.Z) >= 1.5;
		local d = Dl(Q.X) or Dl(Q.Y) or Dl(Q.Z);
		if l or d then
			local r, q = El(w, Q);
			if l then
				local Q, S, w, q, l = Ul(instanceId(G), r, e);
				Fl[#Fl + 1] = Q;
				if S and m then
					for d = 0, 8, 1 do
						local f = (Zl * d) / 8;
						if hl(Al(r, S, w, q, l, f), m.X, m.Z, Vl) then
							N[#N + 1] = { key = "g" .. tostring(instanceId(G)), zone = Q, hitAt = e + f };
							break;
						end;
					end;
				end;
			end;
			if Dl(q) then
				S[#S + 1] = r;
			end;
		end;
		if not l and (not d and ((G.Transparency or 0)) < .95) then
			local r, S, w, l = gl(instanceId(G), q, math.max(Q.X, Q.Y, Q.Z), e);
			Fl[#Fl + 1] = r;
			if l and m then
				local Q, d = m.X - q.X, m.Z - q.Z;
				local f = Q * S + d * w;
				local z = math.abs(d * S - Q * w);
				if f > 0 and z < r.h2 + 1.5 then
					N[#N + 1] = { key = "p" .. tostring(instanceId(G)), zone = r, hitAt = e + f / l };
				end;
			end;
		end;
	end;
	local function q(m, G)
		G = G or 0;
		for m, r in ipairs(m:GetChildren()) do
			if G < 2 and ((r.ClassName == "Folder" or r.ClassName == "Model")) then
				q(r, G + 1);
			else
				w(r);
			end;
		end;
	end;
	for m, G in ipairs(jl) do
		local r = workspace:FindFirstChild(G);
		if r then
			q(r);
		end;
	end;
	local l = {};
	for G, r in ipairs(Ll(e)) do
		local Q, e = nil, 0;
		for m, G in ipairs(r:GetChildren()) do
			local r, N = pcall(function()
					return G.Size;
				end);
			if r and typeof(N) == "Vector3" then
				local m, r = math.min(N.X, N.Y, N.Z), math.max(N.X, N.Y, N.Z);
				if r >= 3 and r / 2 > e then
					Q, e = G.Position, r / 2;
				end;
				if m < .2 and (r >= 3 and ((G.Transparency or 0)) < .95) then
					local m, r = El(G.CFrame, N);
					if r < .2 then
						S[#S + 1] = m;
					end;
				end;
			end;
		end;
		if Q and ((not m or ((Q.X - m.X)) ^ 2 + ((Q.Z - m.Z)) ^ 2 < 3600)) then
			Fl[#Fl + 1] = {
					x = Q.X,
					z = Q.Z,
					ax = 1,
					az = 0,
					bx = 0,
					bz = 1,
					h1 = e,
					h2 = e,
					circle = true,
					pm = Vl,
				};
			l[#l + 1] = { x = Q.X, z = Q.Z, block = e + Vl };
		end;
	end;
	J = l;
	for G, r in ipairs(workspace:GetChildren()) do
		if r.ClassName == "Part" then
			local G = r.Size;
			if typeof(G) == "Vector3" then
				local Q, e = math.min(G.X, G.Y, G.Z), math.max(G.X, G.Y, G.Z);
				if Q < .2 and (e >= 3 and (e <= 30 and ((r.Transparency or 0)) < .95)) then
					local Q = r.Position;
					if not m or ((Q.X - m.X)) ^ 2 + ((Q.Z - m.Z)) ^ 2 < 3600 then
						local m, Q = El(r.CFrame, G);
						if Q < .2 then
							m.pm = Vl;
							Fl[#Fl + 1] = m;
							S[#S + 1] = m;
						end;
					end;
				end;
			end;
		end;
	end;
	for G, r in pairs(el) do
		if r.owned and (r.x and (not r.dead and ((r.phase == "windup" or r.phase == "strike")))) then
			if not m or ((r.x - m.X)) ^ 2 + ((r.z - m.Z)) ^ 2 < 3600 then
				Fl[#Fl + 1] = {
						x = r.x,
						z = r.z,
						ax = 1,
						az = 0,
						bx = 0,
						bz = 1,
						h1 = vl,
						h2 = vl,
						circle = true,
						pm = 2,
					};
			end;
		end;
	end;
	for m, G in pairs(nl) do
		if e - G.t > 1 then
			nl[m] = nil;
		end;
	end;
	for m, G in pairs(Tl) do
		if e - G.t > 1 then
			Tl[m] = nil;
		end;
	end;
	r.zoneCount = #Fl;
	r.zones = Fl;
	if Q.autoRoll then
		al(S, G or d());
		for m, G in ipairs(N) do
			local r = Cl[G.key];
			Cl[G.key] = {
					zone = G.zone,
					p = 0,
					t0 = r and r.t0 or e,
					hitAt = G.hitAt,
					seen = true,
					rolled = r and r.rolled,
				};
		end;
	end;
end;
local function ul(m, G, r, Q)
	local e, N = G - m.x, r - m.z;
	local S = e * m.ax + N * m.az;
	local w = e * m.bx + N * m.bz;
	if m.circle then
		local G = m.h1 + Q;
		local r = math.sqrt(S * S + w * w);
		if r >= G then
			return nil;
		end;
		if r < .2 then
			return G, m.ax, m.az;
		end;
		return G - r, e / r, N / r;
	end;
	local q, l = ((m.h1 + Q)) - math.abs(S), ((m.h2 + Q)) - math.abs(w);
	if q <= 0 or l <= 0 then
		return nil;
	end;
	if q < l then
		local G = S >= 0 and 1 or -1;
		return q, m.ax * G, m.az * G;
	end;
	local d = w >= 0 and 1 or -1;
	return l, m.bx * d, m.bz * d;
end;
local Yl = Q.keepAway;
local pl = {
		W = 87,
		A = 65,
		S = 83,
		D = 68,
	};
local Hl = {};
local function tl(m, G)
	if ((Hl[m] or false)) == G then
		return;
	end;
	Hl[m] = G;
	if G then
		inp.key(pl[m], true);
	else
		inp.key(pl[m], false);
	end;
end;
local function Pl()
	for m in pairs(pl) do
		tl(m, false);
	end;
	inp.clearMove();
end;
local Jl, Il, mQ = 81, 49, 50;
local GQ, rQ = nil, nil;
local function QQ(m, G)
	if GQ then
		return false;
	end;
	inp.key(m, true);
	GQ, rQ = m, G;
	return true;
end;
local function eQ(m)
	-- a roll always wins over a pending tool-equip key press
	if GQ and GQ ~= Jl then
		inp.key(GQ, false);
		GQ = nil;
	end;
	if QQ(Jl, m) then
		r.rolls = ((r.rolls or 0)) + 1;
		return true;
	end;
	return false;
end;
local function NQ(m, G)
	if GQ and ((G or m - rQ >= .05)) then
		inp.key(GQ, false);
		GQ = nil;
	end;
end;
local function SQ(m, G)
	if not m then
		Pl();
		return;
	end;
	local r = math.sqrt(m * m + G * G);
	if r < .001 then
		Pl();
		return;
	end;
	m, G = m / r, G / r;
	if Q.background == true then
		-- no key presses in background mode: walk with Humanoid:Move
		inp.setMove(m, G);
		return;
	end;
	local Q = m * A + G * h;
	local e = m * k + G * T;
	tl("W", Q > .38);
	tl("S", Q < -0.38);
	tl("D", e > .38);
	tl("A", e < -0.38);
end;
local wQ, qQ, lQ = false, true, -1000000000.0;
local dQ;
local function fQ(m)
	if d() - lQ < 10 then
		if not m then
			notify("stats scan already ran in the last 10 s", "delve", 3);
		end;
		return;
	end;
	wQ, qQ = true, m;
end;
r.readStats = fQ;
local function zQ()
	wQ = false;
	-- manual stats: skip the scan entirely
	if Q.autoStats == false then
		return;
	end;
	lQ = d();
	r.statsFound = false;
	local ok, objects = pcall(getgc, true);
	local radius, reach;
	local ambiguous = false;
	if ok and type(objects) == "table" then
		for _, object in ipairs(objects) do
			if type(object) == "table" and type(rawget(object, "RuneFind")) == "number" then
				local candidateRadius = rawget(object, "Radius");
				local candidateReach = rawget(object, "Reach");
				if type(candidateRadius) == "number" and candidateRadius >= .1 and candidateRadius <= 10
					and type(candidateReach) == "number" and candidateReach >= .3 and candidateReach <= 20
				then
					if radius and (radius ~= candidateRadius or reach ~= candidateReach) then
						ambiguous = true;
						break;
					end;
					radius, reach = candidateRadius, candidateReach;
				end;
			end;
		end;
	end;
	if radius and not ambiguous then
		Q.radius, Q.reach = radius, reach;
		r.statsFound = true;
	end;
	if dQ then
		dQ();
	end;
	if r.statsFound then
		notify(string.format("radius %.2f  reach %.2f", Q.radius, Q.reach), "delve stats", 4);
	elseif not qQ then
		notify("No unambiguous mining stats found. Current radius and reach kept.", "delve stats", 4);
	end;
end;
local xQ = nil;
local WQ = "idle";
local KQ = l:GetMouse();
local oQ, FQ = nil, nil;
local jQ, RQ = nil, nil;
local CQ = nil;
local function DQ(m, G, Q)
	if CQ and CQ.step < 2 then
		local m, G = CQ.x - KQ.X, CQ.y - KQ.Y;
		if jQ and ((math.abs(m - jQ) <= 3 and math.abs(G - RQ) <= 3)) then
			oQ, FQ = m, G;
		end;
		jQ, RQ = m, G;
	end;
	local e, N;
	if oQ then
		e, N = m + oQ, G + FQ;
	else
		local inset = guiService:GetGuiInset();
		e, N = m + inset.X, G + inset.Y;
	end;
	local S, w;
	if CQ then
		S, w = CQ.fx, CQ.fy;
	end;
	if oQ then
		local m, G = KQ.X + oQ, KQ.Y + FQ;
		if not S or (CQ.step < 2 and math.abs(m - CQ.x) + math.abs(G - CQ.y) > 6) then
			S, w = m, G;
		end;
	end;
	local q = .5;
	if S and q > 0 then
		local m = CQ and math.min(Q - CQ.t, .1) or .016666666666667;
		local G = 1 - ((q * .9)) ^ ((m * 60));
		S, w = S + ((e - S)) * G, w + ((N - w)) * G;
		if math.abs(e - S) + math.abs(N - w) < 1 then
			S, w = e, N;
		end;
	else
		S, w = e, N;
	end;
	local l, d = math.floor(S + .5), math.floor(w + .5);
	local f = CQ and math.abs(l - CQ.x) + math.abs(d - CQ.y) or 99;
	if not CQ or f > 0 then
		inp.mouseMove(l, d);
	end;
	CQ = {
			x = l,
			y = d,
			fx = S,
			fy = w,
			step = f,
			t = Q,
		};
	r.mouseOffset = oQ and string.format("%d,%d", oQ, FQ) or "measuring";
end;
local function EQ(m, G)
	local r = cQ(m);
	local Q = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize;
	if not r or not Q or r.X < 0 or r.Y < 0 or r.X > Q.X or r.Y > Q.Y then
		CQ = nil;
		return;
	end;
	DQ(r.X, r.Y, G);
end;
local aQ = {
		eval = 0,
		poll = 0,
		sweep = 0,
		refresh = 0,
		dead = 0,
		tool = 0,
		haz = -1,
		ping = 0,
	};
local function iQ()
	-- in background mode nothing touches the mouse/keyboard, so an open menu doesn't need to pause the farm
	if Q.background == true then
		return false;
	end;
	return r.win and ((r.win.alive and r.win:IsVisible()));
end;
local function sQ()
	local m = l.Character;
	local G = m and m:FindFirstChild("HumanoidRootPart");
	return G and G.Position, m;
end;
local function OQ(m)
	if Q.autoEquip == false then
		return;
	end;
	if m - aQ.tool < .25 then
		return;
	end;
	aQ.tool = m;
	local G = nil;
	if WQ == "combat" and ((Q.combat and xQ)) then
		G = "weapon";
	elseif WQ == "mine" and ((Q.mine and L)) then
		G = "pickaxe";
	end;
	if not G or not inp.active() or iQ() then
		return;
	end;
	if m - ((r.toolPressAt or -1000000000.0)) < .8 then
		return;
	end;
	local e = l.Character;
	if not e then
		return;
	end;
	local N;
	if G == "weapon" then
		N = e:GetAttribute("WeaponDrawn");
	else
		N = e:GetAttribute("PickaxeOut");
	end;
	if N == true then
		r.toolTry = nil;
		return;
	end;
	if Q.background == true and Q.useLearned ~= false then
		local learned = inp.learned[G];
		if learned and learned[1] then
			-- background: replay the game's own equip remotes instead of pressing a key
			if inp.replay(G) then
				r.toolPressAt = m;
				r.toolPresses = ((r.toolPresses or 0)) + 1;
			end;
			return;
		end;
	end;
	local tk = G == "weapon" and mQ or Il;
	local last = r.toolTry;
	if last and last.key == tk and Q.background == true and not inp.focused() then
		-- the previous press changed nothing while tabbed out: send this key a different way
		local mode = inp.rotateKey(tk);
		if m - (r.toolNoteAt or -100) > 3 then
			r.toolNoteAt = m;
			notify(string.format("%s key had no effect, trying key method: %s", G, mode), "Delve");
		end;
	end;
	if QQ(tk, m) then
		r.toolPressAt = m;
		r.toolPresses = ((r.toolPresses or 0)) + 1;
		r.toolTry = { key = tk, t = m };
	end;
end;
local VQ = {
		seenAt = nil,
		check = 0,
		phase = "idle",
		t = 0,
		bx = 0,
		by = 0,
	};
r.replays = r.replays or 0;
local function yQ(m)
	if not m:IsA("GuiObject") or not m.Visible then return nil; end;
	local size = m.AbsoluteSize;
	if size.X < 1 or size.Y < 1 then return nil; end;
	return size.X, size.Y;
end;
local function bQ()
	local m = l:FindFirstChild("PlayerGui");
	local G = m and m:FindFirstChild("RunEnd");
	local r = G and G:FindFirstChild("Verbs");
	return r and r:FindFirstChild("Again");
end;
local function vQ()
	if VQ.phase == "down" then
		inp.mouseUp();
	end;
	VQ.phase = "idle";
end;
local function nQ(m)
	if not Q.autoReplay then
		vQ();
		VQ.seenAt = nil;
		return false;
	end;
	if m - VQ.check >= .5 then
		VQ.check = m;
		if workspace:FindFirstChild("RunEndRoom") then
			VQ.seenAt = VQ.seenAt or m;
		else
			VQ.seenAt = nil;
			vQ();
		end;
	end;
	if not VQ.seenAt or m - VQ.seenAt < Q.replayDelay then
		return false;
	end;
	if not inp.active() or iQ() then
		vQ();
		return false;
	end;
	if VQ.phase == "idle" then
		if m - VQ.t < 3 then
			return false;
		end;
		local G = bQ();
		if not G then
			return false;
		end;
		if Q.background == true then
			-- no mouse in background mode: fire the button directly
			VQ.t = m;
			if inp.clickGui(G) then
				r.replays = r.replays + 1;
			end;
			return true;
		end;
		local r = G.AbsolutePosition;
		local Q, e = yQ(G);
		if not Q then return false; end;
		VQ.bx, VQ.by = r.X + Q / 2, r.Y + e / 2;
		VQ.phase, VQ.t = "move", m;
	end;
	if VQ.phase == "move" then
		DQ(VQ.bx, VQ.by, m);
		local G = math.abs(KQ.X - VQ.bx) <= 6 and math.abs(KQ.Y - VQ.by) <= 6;
		if G and ((CQ and CQ.step == 0)) then
			VQ.phase, VQ.t = "settle", m;
		elseif m - VQ.t > 2 then
			VQ.phase, VQ.t = "idle", m;
		end;
	elseif VQ.phase == "settle" then
		DQ(VQ.bx, VQ.by, m);
		if m - VQ.t >= .1 then
			inp.mouseDown();
			VQ.phase, VQ.t = "down", m;
		end;
	elseif VQ.phase == "down" then
		if m - VQ.t >= .08 then
			inp.mouseUp();
			r.replays = r.replays + 1;
			VQ.phase, VQ.t = "idle", m;
		end;
	end;
	return true;
end;
local gQ = { dps = 1, mining = 1 };
local function ZQ(m, G, r)
	local Q = m:upper();
	if Q:find("TAKEN", 1, true) then
		return 0;
	end;
	local e = 0;
	if Q:find("MINE", 1, true) then
		e = r.mining;
	elseif Q:find("WEAPON", 1, true) or Q:find("DAMAGE", 1, true) or Q:find("CRIT", 1, true) then
		e = r.dps;
	end;
	if e == 0 then
		return 0;
	end;
	local N = tonumber(Q:match("([+-]?%d+)%%")) or tonumber(G:match("([+-]?%d+)%%")) or 0;
	return e * N;
end;
local kQ = { "COLLAPSE", "TAKEN" };
local TQ = { "MORE ELITES" };
local function AQ(m, G)
	local r = m:upper();
	for m, G in ipairs(TQ) do
		if r:find(G, 1, true) then
			return true;
		end;
	end;
	local Q = tonumber(r:match("([+-]?%d+)%%")) or tonumber(G:match("([+-]?%d+)%%")) or 0;
	if Q >= 0 then
		return false;
	end;
	for m, G in ipairs(kQ) do
		if r:find(G, 1, true) then
			return false;
		end;
	end;
	return true;
end;
local hQ = {
		MYTHIC = 5,
		LEGENDARY = 4,
		EPIC = 3,
		RARE = 2,
		COMMON = 1,
	};
local function UQ(m, G)
	local r = m:FindFirstChild("Stat");
	local Q = m:FindFirstChild("Bonus");
	local e = r and r.Text or "";
	local N = Q and Q.Text or "";
	local S = 0;
	for m in e:gmatch("[^\n]+") do
		if AQ(m, N) then
			return nil;
		end;
		S = S + ZQ(m, N, G);
	end;
	return S;
end;
local function BQ()
	local m = l:FindFirstChild("PlayerGui");
	local G = m and m:FindFirstChild("RelicDraft");
	local r = G and G:FindFirstChild("Panel");
	local Q = r and r:FindFirstChild("Main");
	if not Q then
		return nil;
	end;
	local e = gQ;
	local N, S = nil, 0;
	for m, G in ipairs(Q:GetChildren()) do
		local r = G:FindFirstChild("Action");
		if G.Name:match("^Card%d+$") and r then
			local m = G:FindFirstChild("Tier");
			local Q = m and m.Text or "";
			if Q == "MYTHIC" then
				return r;
			end;
			local w = UQ(G, e);
			if w then
				local m = ((hQ[Q] or 0)) * 1000 + w;
				if m > S then
					N, S = r, m;
				end;
			end;
		end;
	end;
	return N;
end;
local MQ = {
		check = 0,
		phase = "idle",
		t = 0,
		bx = 0,
		by = 0,
	};
local function LQ(m)
	if not Q.cardPick or iQ() or not inp.active() then
		if MQ.phase == "down" then
			inp.mouseUp();
		end;
		MQ.phase = "idle";
		return false;
	end;
	if MQ.phase == "idle" then
		if m - MQ.check < .8 then
			return false;
		end;
		MQ.check = m;
		if not inp.active() or iQ() or bQ() then
			return false;
		end;
		local G = BQ();
		if not G then
			return false;
		end;
		if Q.background == true then
			if inp.clickGui(G) then
				r.cardPicks = ((r.cardPicks or 0)) + 1;
			end;
			return true;
		end;
		local r = G.AbsolutePosition;
		local width, height = yQ(G);
		if not width then return false; end;
		MQ.bx, MQ.by = r.X + width / 2, r.Y + height / 2;
		MQ.phase, MQ.t = "move", m;
	end;
	if MQ.phase == "move" then
		DQ(MQ.bx, MQ.by, m);
		local G = math.abs(KQ.X - MQ.bx) <= 6 and math.abs(KQ.Y - MQ.by) <= 6;
		if G and m - MQ.t >= .15 then
			inp.mouseDown();
			MQ.phase, MQ.t = "down", m;
		elseif m - MQ.t > 2 then
			MQ.phase = "idle";
			return false;
		end;
	elseif MQ.phase == "down" and m - MQ.t >= .08 then
		inp.mouseUp();
		r.cardPicks = ((r.cardPicks or 0)) + 1;
		MQ.phase, MQ.t = "idle", m;
	end;
	return true;
end;
local function uQ(now, force)
	local character = l.Character;
	local tool = character and character:FindFirstChildOfClass("Tool");
	if character ~= r.rangeCharacter or tool ~= r.rangeTool then
		r.rangeCharacter, r.rangeTool = character, tool;
		r.range, r.rangeSeenAt, r.rangeCheckedAt = nil, nil, nil;
	end;
	if not Q.autoCombatStats or not character or character:GetAttribute("WeaponDrawn") == false then
		r.range, r.rangeSeenAt, r.rangeCheckedAt = nil, nil, nil;
		return;
	end;
	if not force and r.rangeCheckedAt and now - r.rangeCheckedAt < .25 then return; end;
	r.rangeCheckedAt = now;

	-- Use the same attack-cone geometry the existing combat loop reads.
	local cone = workspace:FindFirstChild("WeaponCone");
	local detected;
	if cone then
		for _, part in ipairs(cone:GetChildren()) do
			if part:IsA("BasePart") and part.Size.X < .3 and part.Size.Z > 1 then
				detected = math.max(detected or 0, part.Size.Z);
			end;
		end;
	end;
	if detected then
		r.range, r.rangeSeenAt = detected, now;
	elseif r.rangeSeenAt and now - r.rangeSeenAt > 4 then
		r.range, r.rangeSeenAt = nil, nil;
	end;
end;
local function YQ()
	local manual = tonumber(Q.fightDist) or 8;
	if Q.autoCombatStats and r.range then
		return math.min(r.range * .7, manual);
	end;
	return manual;
end;
local function pQ(m, G)
	if not a or #i < 3 then
		return true;
	end;
	local r, Q = g(a, m, G);
	for m, G in ipairs({
		{ -0.15, -0.15 },
		{ .15, -0.15 },
		{ -0.15, .15 },
		{ .15, .15 },
	}) do
		if not V[math.floor(((r + G[1])) + .5) * 4096 + math.floor(((Q + G[2])) + .5)] then
			return false;
		end;
	end;
	return true;
end;
r.walkable = pQ;
local function centerFarmAnchor(position)
	-- A visible chest can be used even before it unlocks.
	local saved = r.centerFarmChest;
	if saved and pQ(saved.x, saved.z) then return saved.x, saved.z; end;
	local chest, nearest;
	for _, candidate in pairs(r.chestScanPlate == E and ql or {}) do
		local distance = (candidate.x - position.X)^2 + (candidate.z - position.Z)^2;
		if (not nearest or distance < nearest) and pQ(candidate.x, candidate.z) then
			chest, nearest = candidate, distance;
		end;
	end;
	if chest then
		r.centerFarmChest = chest;
		return chest.x, chest.z;
	end;

	-- Snap the midpoint of the floor bounds to a real tile, even on irregular floors.
	if #i == 0 then return nil; end;
	if r.centerFarmTiles ~= i then
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge;
		for _, tile in ipairs(i) do
			minX, maxX = math.min(minX, tile.wx), math.max(maxX, tile.wx);
			minZ, maxZ = math.min(minZ, tile.wz), math.max(maxZ, tile.wz);
		end;
		local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2;
		local center, nearestTile;
		for _, tile in ipairs(i) do
			local distance = (tile.wx - midX)^2 + (tile.wz - midZ)^2;
			if not nearestTile or distance < nearestTile then
				center, nearestTile = tile, distance;
			end;
		end;
		r.centerFarmTiles, r.centerFarmTile = i, center;
	end;
	return r.centerFarmTile.wx, r.centerFarmTile.wz;
end;
local function HQ(m, G)
	if a and #i >= 3 then
		local G, r = g(a, m.X, m.Z);
		if not V[math.floor(G + .5) * 4096 + math.floor(r + .5)] then
			return 0;
		end;
	end;
	local r = 0;
	if not pQ(m.X + G[1] * 2.5, m.Z + G[2] * 2.5) then
		r = r + 1;
	end;
	if not pQ(m.X + G[1] * 5, m.Z + G[2] * 5) then
		r = r + 1;
	end;
	return r;
end;
local function tQ()
	local m = .7071;
	return {
		{ A, h },
		{ -A, -h },
		{ k, T },
		{ -k, -T },
		{ ((A + k)) * m, ((h + T)) * m },
		{ ((A - k)) * m, ((h - T)) * m },
		{ ((-A + k)) * m, ((-h + T)) * m },
		{ ((-A - k)) * m, ((-h - T)) * m },
	};
end;
local function PQ(m, G)
	local r = 0;
	for Q, e in ipairs(Fl) do
		local N = ul(e, m, G, e.pm or Yl);
		if N then
			r = ((r + N)) + 1;
			local Q = ul(e, m, G, Vl);
			if Q then
				r = r + ((Q + 1)) * 6;
			end;
		end;
	end;
	return r;
end;
local JQ;
local function IQ(m)
	if not inp.active() or m - ((r.lastRoll or -1000000000.0)) < yl then
		return;
	end;
	local G = sQ();
	if not G then
		return;
	end;
	for r, Q in pairs(Cl) do
		if not Q.rolled and (Q.hitAt and (Q.hitAt > m and (Q.hitAt - m < yl and ul(Q.zone, G.X, G.Z, Vl)))) then
			return;
		end;
	end;
	for Q, e in pairs(el) do
		if e.owned and (e.strikeAt and (e.rolledFor ~= e.strikeAt and m - e.strikeAt < .15)) then
			e.rolledFor = e.strikeAt;
			for Q, N in ipairs(Fl) do
				if ul(N, G.X, G.Z, Vl) then
					if eQ(m) then
						r.lastRoll = m;
						f(string.format("strike roll vs %s", tostring(e.name)));
					end;
					return;
				end;
			end;
		end;
	end;
	-- roll BEFORE the strike: once a mob's windup length is learned, schedule the roll from the windup start
	if Q.windupLearn ~= false and r.windups then
		local lead = bl + (r.pingLead or 0);
		for _, mob in pairs(el) do
			local dur = mob.owned and mob.phase == "windup" and mob.windupAt and mob.x and r.windups[mob.name];
			if dur and mob.rolledForW ~= mob.windupAt then
				local hitAt = mob.windupAt + dur;
				if m >= hitAt - lead and m <= hitAt + .12 then
					local dx, dz = mob.x - G.X, mob.z - G.Z;
					local reach = vl + Vl;
					if dx * dx + dz * dz <= reach * reach then
						if eQ(m) then
							mob.rolledForW = mob.windupAt;
							r.lastRoll = m;
							f(string.format("windup roll vs %s (%.2fs windup)", tostring(mob.name), dur));
						end;
						return;
					end;
				end;
			end;
		end;
	end;
end;
local function mh(m)
	NQ(m);
	IQ(m);
	if not next(Cl) then
		JQ = nil;
		return;
	end;
	local G = sQ();
	if not G then
		return;
	end;
	local Q, e = 0, 0;
	if JQ and m - JQ.t > .001 then
		Q, e = ((G.X - JQ.x)) / ((m - JQ.t)), ((G.Z - JQ.z)) / ((m - JQ.t));
	end;
	if not JQ or m - JQ.t >= .05 then
		JQ = { x = G.X, z = G.Z, t = m };
	end;
	local N = bl + (r.pingLead or 0);
	for S, w in pairs(Cl) do
		if not w.rolled then
			local S = (w.hitAt and m >= w.hitAt - N) or (not w.hitAt and w.p >= .9);
			if S and ((not w.hitAt or m <= w.hitAt + .1)) then
				local N = w.hitAt and math.max(w.hitAt - m, 0) or 0;
				if ul(w.zone, G.X + Q * N, G.Z + e * N, Vl) and (inp.active() and m - ((r.lastRoll or -1000000000.0)) >= yl) then
					if eQ(m) then
						w.rolled = true;
						r.lastRoll = m;
						f(string.format("roll zone=%.1f,%.1f hitIn=%.2f", w.zone.x, w.zone.z, ((w.hitAt or m)) - m));
					end;
				end;
			end;
		end;
	end;
end;
local Gh = {
		3,
		6,
		9,
		12,
		16,
		20,
		25,
	};
local rh = 16;
local Qh = nil;
local function eh(m, G, r)
	for m, Q in ipairs(m) do
		if ul(Q, G, r, Vl + .5) then
			return true;
		end;
	end;
	return false;
end;
local function Nh(m, G, r)
	if Qh and (r - Qh.t < .25 and not eh(Fl, Qh.x, Qh.z)) then
		return Qh;
	end;
	local Q = {};
	for r, e in ipairs(Fl) do
		local N = math.max(e.h1, e.h2) + 30;
		if ((e.x - m)) ^ 2 + ((e.z - G)) ^ 2 < N * N then
			Q[#Q + 1] = e;
		end;
	end;
	local e = {};
	for r, N in ipairs(Gh) do
		for r = 0, rh - 1, 1 do
			local S = (((r / rh)) * math.pi) * 2;
			local w, q = m + math.cos(S) * N, G + math.sin(S) * N;
			if pQ(w, q) and not eh(Q, w, q) then
				e[#e + 1] = { x = w, z = q, d = N };
			end;
		end;
		if #e >= 12 then
			break;
		end;
	end;
	local N, S = nil, nil;
	for r, e in ipairs(e) do
		local w = 0;
		local q = math.max(1, math.floor(e.d / 1.5));
		for r = 1, q - 1, 1 do
			local N = r / q;
			if eh(Q, m + ((e.x - m)) * N, G + ((e.z - G)) * N) then
				w = w + 1;
			end;
		end;
		local l = e.d + w * 5;
		if not S or l < S then
			N, S = e, l;
		end;
	end;
	Qh = N and { x = N.x, z = N.z, t = r } or nil;
	return Qh;
end;
local Sh, wh = 1, 0;
local function qh(m, G, e, N)
	local S = Kl(G, N);
	local w = YQ();
	local q, l = m.X - S.X, m.Z - S.Z;
	local d = math.sqrt(q * q + l * l);
	if d < .001 then
		q, l, d = k, T, 1;
	end;
	local z, c = ((-l / d)) * Sh, ((q / d)) * Sh;
	local x = {};
	for m, r in ipairs(e) do
		if r ~= G then
			x[#x + 1] = Kl(r, N);
		end;
	end;
	local function W(m, G)
		local r = 0;
		for Q, e in ipairs(x) do
			if ((e.X - m)) ^ 2 + ((e.Z - G)) ^ 2 < 12.25 then
				r = r + 1;
			end;
		end;
		return r;
	end;
	local K = Q.dodge;
	if K and eh(Fl, m.X, m.Z) then
		local G = Nh(m.X, m.Z, N);
		if G then
			if not r.dodging then
				f(string.format("escape to open ground (combat) %.1f studs away, zones=%d", math.sqrt(((G.x - m.X)) ^ 2 + ((G.z - m.Z)) ^ 2), #Fl));
			end;
			r.dodging = true;
			SQ(G.x - m.X, G.z - m.Z);
			return;
		end;
	end;
	local o = tQ();
	local F = K and PQ(m.X, m.Z) or 0;
	local j = nil;
	local R = F > 0 and 0 or 1;
	local C = ((((F * 24 + (math.abs(d - w) * .8) * R)) + .4)) + W(m.X, m.Z) * 1.5;
	for G, r in ipairs(o) do
		local Q, e = m.X + r[1] * 2.5, m.Z + r[2] * 2.5;
		local N, q = m.X + r[1] * 5, m.Z + r[2] * 5;
		local l = K and ((PQ(Q, e) + PQ(N, q)) + PQ(m.X + r[1] * 7.5, m.Z + r[2] * 7.5)) or 0;
		local d = math.sqrt(((N - S.X)) ^ 2 + ((q - S.Z)) ^ 2);
		local f = ((((((l * 8 + HQ(m, r) * 40)) + (math.abs(d - w) * .8) * R)) - (((r[1] * z + r[2] * c)) * 1.2) * R)) + W(N, q) * 1.5;
		if f < C then
			j, C = r, f;
		end;
	end;
	if j and ((j[1] * z + j[2] * c < -0.3 and N - wh > 1.5)) then
		Sh = -Sh;
		wh = N;
	end;
	if F > 0 and not r.dodging then
		f(string.format("dodge start (combat) zones=%d danger=%.1f dir=%s", #Fl, F, j and string.format("%.2f,%.2f", j[1], j[2]) or "stay"));
	end;
	r.dodging = F > 0;
	if j then
		SQ(j[1], j[2]);
	else
		SQ(nil);
	end;
end;
local function lh(m)
	local G = sQ();
	if not G then
		WQ, L, u, xQ = "idle", nil, nil, nil;
		Pl();
		return;
	end;
	B();
	local e = inp.active();
	local N = false;
	for m, G in pairs(Hl) do
		N = N or G;
	end;
	if inp.moveVec then
		N = true;
	end;
	if N then
		local Q = r.stuckRef;
		if not Q or ((G.X - Q.x)) ^ 2 + ((G.Z - Q.z)) ^ 2 > .25 then
			r.stuckRef = { x = G.X, z = G.Z, t = m };
		elseif m - Q.t > 1.2 then
			Pl();
			r.stuckRef = nil;
			r.unsticks = ((r.unsticks or 0)) + 1;
		end;
	else
		r.stuckRef = nil;
	end;
	local S = ol();
	r.mobCount = #S;
	if #S > 0 and Q.combat then
		WQ = "combat";
	elseif Q.mine then
		WQ = "mine";
	else
		WQ = "idle";
	end;
	xQ = nil;
	local w, q = nil, nil;
	for m, Q in ipairs(S) do
		local e = math.sqrt(((Q.x - G.X)) ^ 2 + ((Q.z - G.Z)) ^ 2);
		Q.d = e;
		if r.keepTarget == Q.addr then
			e = e - 4;
		end;
		if not q or e < q then
			w, q = Q, e;
		end;
	end;
	if WQ == "combat" and ((Q.combat and w)) then
		xQ = w.addr;
		r.keepTarget = w.addr;
	else
		r.keepTarget = nil;
	end;
	if WQ == "mine" then
		if y(m) then
			Ql(G, m);
		else
			L, u = nil, nil;
		end;
	else
		L, u = nil, nil;
		if y(m) then
			a = n({});
		end;
	end;
	r.mode, r.walkTo, r.aimAt = WQ, u ~= nil, L ~= nil;
	if not e or iQ() then
		Pl();
		return;
	end;
	if Q.dodge or Q.autoRoll then
		-- the per-frame hazard scan in r.step already refreshed Fl this frame
		if aQ.haz ~= m then
			Xl(G, m);
		end;
	elseif #Fl > 0 or next(Cl) then
		Fl, Cl = {}, {};
	end;
	if WQ == "combat" then uQ(m); end;
	if WQ == "combat" and ((Q.combat and ((Q.chase and w)))) then
		qh(G, w, S, m);
		return;
	end;
	if Q.dodge and (#Fl > 0 and eh(Fl, G.X, G.Z)) then
		local Q = Nh(G.X, G.Z, m);
		if Q then
			if not r.dodging then
				f(string.format("escape to open ground %.1f studs away, zones=%d", math.sqrt(((Q.x - G.X)) ^ 2 + ((Q.z - G.Z)) ^ 2), #Fl));
			end;
			r.dodging = true;
			SQ(Q.x - G.X, Q.z - G.Z);
			return;
		end;
	end;
	if Q.dodge and #Fl > 0 then
		local m, Q, e = 0, 0, false;
		for r, N in ipairs(Fl) do
			local S, w, q = ul(N, G.X, G.Z, N.pm or Yl);
			if S then
				e = true;
				m, Q = m + w * S, Q + q * S;
			end;
		end;
		if e then
			local e = math.sqrt(m * m + Q * Q);
			if e < .001 then
				m, Q, e = k, T, 1;
			end;
			local N, S = nil, nil;
			for r, w in ipairs(tQ()) do
				local q = (PQ(G.X + w[1] * 2.5, G.Z + w[2] * 2.5) + PQ(G.X + w[1] * 5, G.Z + w[2] * 5)) + PQ(G.X + w[1] * 7.5, G.Z + w[2] * 7.5);
				local l = ((q * 8 + HQ(G, w) * 40)) - ((((w[1] * m + w[2] * Q)) / e)) * 2;
				if not S or l < S then
					N, S = w, l;
				end;
			end;
			if not r.dodging then
				f(string.format("dodge start (out of combat) zones=%d dir=%.2f,%.2f", #Fl, N[1], N[2]));
			end;
			SQ(N[1], N[2]);
			r.dodging = true;
			return;
		end;
	end;
	r.dodging = false;
	if WQ == "mine" and Q.centerFarm and E then
		local anchorX, anchorZ = centerFarmAnchor(G);
		if anchorX then
			r.chestWalk = false;
			local dx, dz = anchorX - G.X, anchorZ - G.Z;
			local atAnchor = dx * dx + dz * dz <= 1.25^2;
			local strays = (r.posCount or 0) > 0;
			local cleanup = Q.centerCleanup ~= false;
			if r.strayTrip and (not strays or not cleanup) then
				r.strayTrip = false;
			end;
			if L and (atAnchor or r.strayTrip) then
				-- something is in reach from here: stand still and mine it
				SQ(nil);
				return;
			end;
			if not L and cleanup and strays and u and (r.strayTrip or (atAnchor and r.noAimSince and m - r.noAimSince > .8)) then
				-- ores the anchor can't reach (edge of the arena / off screen): walk to them, then head back
				r.strayTrip = true;
				SQ(u.X - G.X, u.Z - G.Z);
				return;
			end;
			if atAnchor then
				SQ(nil);
			else
				L = nil;
				r.progressAt = m;
				SQ(dx, dz);
			end;
			return;
		end;
	end;
	if Q.chests and WQ ~= "combat" then
		local m = cl(G);
		if m then
			local Q, e = m.x - G.X, m.z - G.Z;
			if Q * Q + e * e > 1 then
				r.chestWalk = true;
				SQ(Q, e);
				return;
			end;
		end;
	end;
	r.chestWalk = false;
	if WQ == "mine" and ((Q.walk and u)) then
		SQ(u.X - G.X, u.Z - G.Z);
		return;
	end;
	SQ(nil);
end;
-- main frame step (kept in r.step so the connection below can pcall it)
r.step = function()
		local m = d();
		local blockedInput = missingInput and Q.background ~= true;
		if blockedInput or iQ() then
			if not blockedInput then
				Pl();
				inp.clearAim();
				NQ(m, true);
				vQ();
				if MQ.phase == "down" then inp.mouseUp(); end;
				MQ.phase = "idle";
			end;
			if wQ and not blockedInput then zQ(); end;
			if dQ and m - aQ.poll >= .1 then aQ.poll = m; dQ(); end;
			return;
		end;
		if wQ then
			zQ();
			return;
		end;
		if Q.autoStats ~= false and not r.statsFound and ((((r.rockCount or 0)) > 0 and m - lQ > 20)) then
			fQ(true);
		end;
		if m - aQ.poll >= .1 then
			aQ.poll = m;
			if ((Q.on and true or false)) ~= r.farmOn then
				N(Q.on);
			end;
			if dQ then
				dQ();
			end;
		end;
		-- network ping (one way) so rolls are sent early enough to land before the hit
		if m - aQ.ping >= .5 then
			aQ.ping = m;
			local okPing, ping = pcall(l.GetNetworkPing, l);
			r.pingLead = (Q.pingComp ~= false and okPing and type(ping) == "number") and math.min(ping, .25) or 0;
		end;
		local G = Q.combat or Q.chests or (Q.on and Q.centerFarm);
		if G then
			if m - aQ.sweep >= .5 then
				aQ.sweep, aQ.refresh = m, m;
				zl(m);
			elseif m - aQ.refresh >= .016 then
				aQ.refresh = m;
				xl(m);
			end;
			if xQ and ((el[xQ] and m - aQ.dead >= .25)) then
				aQ.dead = m;
				Wl(xQ, el[xQ], m);
			end;
		elseif next(el) then
			el = {};
		end;
		-- scan attack telegraphs every frame (the slow eval loop below is too late for fast attacks)
		if Q.dodge or Q.autoRoll then
			if inp.active() then
				local hazardPos = sQ();
				if hazardPos then
					aQ.haz = m;
					Xl(hazardPos, m);
				end;
			end;
		end;
		if m - aQ.eval >= ((((#Fl > 0 or next(Cl))) and .033 or .1)) then
			aQ.eval = m;
			lh(m);
		end;
		if Q.autoRoll and not iQ() then
			mh(m);
		else
			NQ(m);
		end;
		OQ(m);
		local e = nQ(m) or LQ(m);
		if not e and m - ((aQ.aim or 0)) >= .016666666666667 then
			aQ.aim = m;
			local G = nil;
			if inp.active() and not iQ() then
				local r = xQ and el[xQ];
				if r and ((WQ == "combat" and Q.combat)) then
					G = Kl(r, m);
				elseif WQ == "mine" and ((Q.mine and ((L and a)))) then
					if L.ore then
						local ore = L.ore;
						if ore and ore:IsDescendantOf(workspace) then
							local part = orePart(ore);
							G = part and part.Position;
						end;
					else
						G = Z(a, L.ax, L.az);
					end;
				end;
			end;
			if G then
				if inp.silent() and inp.setAim(G) then
					-- silent aim: the game reads our target instead of the cursor, the real mouse stays put
					CQ = nil;
				else
					inp.clearAim();
					EQ(G, m);
				end;
			else
				CQ = nil;
				inp.clearAim();
			end;
		end;
	end;
local dh = false;
do
	local connection;
	local handlingIdle = false;
	r.connectAntiAfk = function()
		connection = l.Idled:Connect(function()
			if dh or not Q.antiAfk or handlingIdle then return; end;
			local camera = workspace.CurrentCamera;
			if not camera then return; end;

			handlingIdle = true;
			local ok, err = pcall(function()
				local virtualUser = game:GetService("VirtualUser");
				local cameraFrame = camera.CFrame;
				virtualUser:Button2Down(Vector2.zero, cameraFrame);
				task.wait(1);
				virtualUser:Button2Up(Vector2.zero, cameraFrame);
			end);
			handlingIdle = false;
			if ok then
				notify("Idle input sent.", "Delve Anti-AFK");
			else
				notify(tostring(err), "Delve Anti-AFK error");
			end;
		end);
	end;
	r.disconnectAntiAfk = function()
		if connection then
			connection:Disconnect();
			connection = nil;
		end;
	end;
end;
r.stop = function()
		if dh then
			return;
		end;
		dh = true;
		r.disconnectAntiAfk();
		pcall(function()
			r.conn:Disconnect();
		end);
		pcall(function()
			r.conn2:Disconnect();
		end);
		pcall(inp.stop);
		pcall(Pl);
		pcall(vQ);
		if MQ.phase == "down" then
			pcall(inp.mouseUp);
		end;
		pcall(NQ, 0, true);
		if r.win and r.win.alive then
			r.win:Unload();
		end;
		notify("Stopped.", "Delve");
	end;

-- apply settings that are cached in upvalues (and resolve keybinds); safe to call any time
do
	local specialKeys = { Space = 32, Shift = 16, LShift = 160, RShift = 161, Ctrl = 17, Alt = 18, Tab = 9 };
	local function keyCode(name, fallback)
		if type(name) ~= "string" or #name == 0 then
			return fallback;
		end;
		if specialKeys[name] then
			return specialKeys[name];
		end;
		if #name == 1 then
			return string.byte(name:upper());
		end;
		return fallback;
	end;
	local function slotCode(n, fallback)
		n = math.floor(tonumber(n) or fallback);
		if n < 1 or n > 9 then
			n = fallback;
		end;
		return 48 + n;
	end;
	r.sync = function()
		dl = tonumber(Q.chestRange) or 120;
		Yl = tonumber(Q.keepAway) or 7;
		Vl = tonumber(Q.hitMargin) or 1.5;
		vl = tonumber(Q.meleeReach) or 5.5;
		bl = tonumber(Q.rollLead) or .2;
		yl = tonumber(Q.rollCooldown) or 1.05;
		Jl = keyCode(Q.rollKey, 81);
		Il = slotCode(Q.pickSlot, 1);
		mQ = slotCode(Q.weaponSlot, 2);
	end;
	r.sync();
end;

(function()
	-- Settings shared by the controls and the runtime
	local spec = {
		{
			name = "General",
			side = "L",
			items = {
				{ k = "antiAfk", t = "toggle", text = "Anti-AFK" },
				{ k = "autoReplay", t = "toggle", text = "Auto Replay", f = "st_autoreplay" },
				{ k = "cardPick", t = "toggle", text = "Auto-pick relic cards" },
				{ k = "dodgeLog", t = "toggle", text = "Log dodges to file" },
				{ k = "replayDelay", t = "slider", text = "Replay delay", min = .5, max = 10, step = .5, suffix = " s", f = "st_replaydelay" },
				{ k = "chestRange", t = "slider", text = "Chest range", min = 20, max = 300, step = 10, suffix = " st", f = "st_chestrange" },
			},
		},
		{
			name = "Mining",
			side = "L",
			rescan = true,
			items = {
				{ k = "autoStats", t = "toggle", text = "Auto-detect mining stats" },
				{ k = "mineRange", t = "slider", text = "Rock search range", min = 10, max = 400, step = 10, suffix = " st" },
				{ k = "reach", t = "slider", text = "Mining reach", min = .3, max = 20, step = .01, suffix = " st" },
				{ k = "radius", t = "slider", text = "Mining radius", min = .1, max = 10, step = .01, suffix = " st" },
				{ k = "centerOre", t = "toggle", text = "Center aim on ore" },
				{ k = "radiusScale", t = "slider", text = "Mining radius scale", min = .4, max = 1, step = .05, suffix = "x" },
				{ k = "reachScale", t = "slider", text = "Reach safety scale", min = .5, max = 1.5, step = .05, suffix = "x" },
				{ k = "minTier", t = "slider", text = "Min rock tier", min = 1, max = 10, step = 1, suffix = "" },
				{ k = "skipAfter", t = "slider", text = "Skip stuck rock after", min = 3, max = 30, step = 1, suffix = " s" },
			},
		},
		{
			name = "Features",
			side = "L",
			items = {
				{ k = "mine", t = "feat", text = "Mine rocks" },
				{ k = "walk", t = "feat", text = "Walk to rocks" },
				{ k = "combat", t = "feat", text = "Fight mobs" },
				{ k = "chase", t = "feat", text = "Chase and orbit target" },
				{ k = "dodge", t = "feat", text = "Dodge attacks" },
				{ k = "autoRoll", t = "feat", text = "Auto roll" },
				{ k = "chests", t = "feat", text = "Collect chests" },
			},
		},
		{
			name = "Combat & dodging",
			side = "R",
			items = {
				{ k = "autoCombatStats", t = "toggle", text = "Auto-detect sword range" },
				{ k = "fightDist", t = "slider", text = "Orbit distance", min = 2, max = 30, step = 1, suffix = " st", f = "st_fight" },
				{ k = "keepAway", t = "slider", text = "Keep away from attacks", min = 1, max = 12, step = .5, suffix = " st", f = "st_keepaway" },
				{ k = "hitMargin", t = "slider", text = "Hit margin (body size)", min = .5, max = 3, step = .1, suffix = " st", f = "st_hitmargin" },
				{ k = "meleeReach", t = "slider", text = "Melee reach", min = 2, max = 12, step = .5, suffix = " st", f = "st_meleereach" },
				{ k = "rollLead", t = "slider", text = "Roll before hit (higher = earlier)", min = .05, max = .6, step = .05, suffix = " s", f = "st_rolllead" },
				{ k = "rollCooldown", t = "slider", text = "Roll cooldown", min = .3, max = 2, step = .05, suffix = " s" },
				{ k = "pingComp", t = "toggle", text = "Ping compensation" },
				{ k = "windupLearn", t = "toggle", text = "Learn mob windups (roll before strike)" },
			},
		},
		{
			name = "Controls",
			side = "R",
			items = {
				{ k = "autoEquip", t = "toggle", text = "Auto-equip tools" },
				{ k = "pickSlot", t = "slider", text = "Pickaxe slot", min = 1, max = 9, step = 1, suffix = "" },
				{ k = "weaponSlot", t = "slider", text = "Weapon slot", min = 1, max = 9, step = 1, suffix = "" },
				{ k = "rollKey", t = "combo", text = "Roll key", items = { "Q", "E", "R", "F", "C", "V", "X", "Z", "G", "Space", "LShift" } },
			},
		},
		{
			name = "Background",
			side = "R",
			items = {
				{ k = "background", t = "toggle", text = "Background mode (work while tabbed out)" },
				{ k = "silentAim", t = "toggle", text = "Silent aim (don't move my mouse)" },
				{ k = "bgKeyMethod", t = "combo", text = "Background key method", items = { "Auto", "VirtualInputManager", "Input connections" } },
				{ k = "bgMoveMethod", t = "combo", text = "Background walk method", items = { "Both", "Humanoid:Move", "Velocity" } },
				{ k = "useLearned", t = "toggle", text = "Use learned equip remotes in background" },
			},
		},
	};

	local function apply(it, value)
		local key = it.k;
		if it.t == "feat" then
			Q.feat[key] = value and true or false;
			if Q.on then
				Q[key] = Q.feat[key];
			end;
		elseif it.t == "toggle" then
			Q[key] = value and true or false;
			if key == "autoStats" and value then
				r.statsFound = false;
				fQ(true);
			end;
			if key == "background" or key == "silentAim" then
				if value then
					inp.ensureSilent();
				end;
				Pl();
				inp.clearAim();
			end;
		elseif it.t == "slider" then
			local num = tonumber(value);
			if not num then
				return;
			end;
			Q[key] = num;
		elseif it.t == "combo" then
			if type(value) == "number" then
				value = it.items[value];
			end;
			if type(value) == "string" then
				Q[key] = value;
			end;
		end;
		if r.sync then
			r.sync();
		end;
	end;

	-- scan the game's stats and apply them (reach/radius), using a safe reach scale
	local function rescan()
		Q.autoStats = true;
		Q.reachScale = 1;
		r.statsFound = false;
		if r.sync then
			r.sync();
		end;
		fQ(false);
		if dQ then
			dQ();
		end;
	end;

	notify("Loading WindUI…", "Delve Potassium");
	local url = "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua";
	local downloaded, source = pcall(function() return game:HttpGet(url); end);
	assert(downloaded, "WindUI download failed: " .. tostring(source));
	local chunk, compileError = loadstring(source, "WindUI");
	assert(chunk, "WindUI compile failed: " .. tostring(compileError));
	local WindUI = chunk();
	assert(type(WindUI) == "table" and type(WindUI.CreateWindow) == "function", "WindUI did not return its window API");

	local window = WindUI:CreateWindow({
		Title = "Delve | Potassium",
		Folder = "DelvePotassium",
		Icon = "pickaxe",
		Size = UDim2.fromOffset(620, 480),
		ToggleKey = Enum.KeyCode.RightShift,
		OpenButton = {
			Title = "Open Delve",
			Enabled = true,
			Draggable = true,
			OnlyMobile = false,
		},
	});
	local visible = true;
	r.win = {
		alive = true,
		IsVisible = function() return visible; end,
		Unload = function(self)
			self.alive = false;
			window:Destroy();
		end,
	};
	window:OnOpen(function() visible = true; end);
	window:OnClose(function() visible = false; end);
	window:OnDestroy(function()
		r.win.alive = false;
		visible = false;
		r.stop();
	end);

	local main = window:Tab({ Title = "Farm", Icon = "pickaxe" });
	main:Paragraph({
		Title = "Delve",
		Desc = "Enable the farm, then close this panel. Right Shift reopens it.",
	});
	local farmToggle;
	farmToggle = main:Toggle({
		Title = "Farm enabled",
		Value = false,
		Callback = function(enabled)
			local blocker = enabled and farmBlocker();
			if blocker then
				notify(blocker, "Delve");
				if farmToggle then farmToggle:Set(false); end;
				return;
			end;
			N(enabled);
		end,
	});
	main:Toggle({
		Title = "Mine from chest / arena center",
		Desc = "Walk to the chest or center tile, then aim at ores from that spot.",
		Value = Q.centerFarm == true,
		Callback = function(enabled)
			Q.centerFarm = enabled == true;
			if not Q.centerFarm then r.centerFarmChest = nil; r.strayTrip = false; end;
		end,
	});
	main:Toggle({
		Title = "Chase stray ores (center farm)",
		Desc = "If ores are out of reach from the center, walk to them, then return.",
		Value = Q.centerCleanup ~= false,
		Callback = function(enabled)
			Q.centerCleanup = enabled == true;
		end,
	});
	main:Toggle({
		Title = "Background mode (work while tabbed out)",
		Desc = "Walks, rolls and aims without touching your keyboard or mouse, so Roblox can sit behind other windows. Don't minimize it.",
		Value = Q.background == true,
		Callback = function(enabled)
			Q.background = enabled == true;
			if enabled then inp.ensureSilent(); end;
			Pl();
			inp.clearAim();
			if dQ then dQ(); end;
		end,
	});
	main:Button({ Title = "Close settings", Callback = function() window:Close(); end });
	main:Button({ Title = "Stop and unload", Callback = r.stop });

	local synced = {};
	local function current(item)
		if item.t == "feat" then return Q.feat[item.k] ~= false; end;
		return Q[item.k];
	end;
	for _, group in ipairs(spec) do
		local tab = window:Tab({ Title = group.name });
		for _, item in ipairs(group.items) do
			local it = item;
			local value = current(it);
			local widget;
			local function changed(newValue)
				apply(it, newValue);
				if synced[it.k] then synced[it.k].value = current(it); end;
			end;
			if it.t == "slider" then
				widget = tab:Slider({
					Title = it.text,
					Step = it.step,
					Value = { Min = it.min, Max = it.max, Default = tonumber(value) or it.min },
					Callback = changed,
				});
			elseif it.t == "combo" then
				widget = tab:Dropdown({
					Title = it.text,
					Values = it.items,
					Value = value,
					AllowNone = false,
					Callback = changed,
				});
			else
				widget = tab:Toggle({ Title = it.text, Value = value == true, Callback = changed });
			end;
			synced[it.k] = { widget = widget, value = value, item = it };
		end;
		if group.rescan then tab:Button({ Title = "Scan mining stats", Callback = rescan }); end;
		if group.name == "Background" then
			tab:Button({
				Title = "Test background support",
				Callback = function()
					notify(inp.report(), "Delve background");
				end,
			});
			tab:Button({
				Title = "Background status",
				Callback = function()
					notify(inp.status(), "Delve background");
				end,
			});
			tab:Button({
				Title = "Test walking (1s)",
				Callback = function()
					task.spawn(inp.testWalk);
				end,
			});
			tab:Button({
				Title = "Test pickaxe equip key",
				Callback = function()
					task.spawn(inp.testEquip, Il, "PickaxeOut", "Pickaxe");
				end,
			});
			tab:Button({
				Title = "Test weapon equip key",
				Callback = function()
					task.spawn(inp.testEquip, mQ, "WeaponDrawn", "Weapon");
				end,
			});
			tab:Button({
				Title = "Learn weapon equip (then press the key in game)",
				Callback = function()
					inp.learn("weapon", mQ);
				end,
			});
			tab:Button({
				Title = "Learn pickaxe equip (then press the key in game)",
				Callback = function()
					inp.learn("pickaxe", Il);
				end,
			});
			tab:Button({
				Title = "Forget learned equips",
				Callback = function()
					inp.learned.weapon, inp.learned.pickaxe = nil, nil;
					notify("Learned equip remotes cleared.", "Delve learn");
				end,
			});
		end;
		if group.name == "Combat & dodging" then
			tab:Button({
				Title = "Report sword range",
				Callback = function()
					uQ(d(), true);
					local message = r.range
						and string.format("Estimated sword range: %.2f studs. Orbit distance: %.2f studs.", r.range, YQ())
						or string.format("No sword range detected. Manual orbit distance: %.2f studs.", YQ());
					notify(message, "Delve combat");
				end,
			});
			tab:Button({
				Title = "Report learned mob windups",
				Callback = function()
					local parts = {};
					for name, dur in pairs(r.windups or {}) do
						parts[#parts + 1] = string.format("%s %.2fs", name, dur);
					end;
					notify(#parts > 0 and table.concat(parts, ", ") or "No windups learned yet. Fight a few mobs first.", "Delve windups");
				end,
			});
		end;
	end;
	dQ = function()
		for _, setting in pairs(synced) do
			local value = current(setting.item);
			if value ~= setting.value and setting.widget and type(setting.widget.Set) == "function" then
				setting.value = value;
				pcall(setting.widget.Set, setting.widget, value);
			end;
		end;
	end;
	window:Open();
end)();

inp.ensureSilent();
r.runStep = function()
		local ok, err = pcall(r.step);
		if not ok then
			pcall(Pl);
			pcall(NQ, 0, true);
			pcall(vQ);
			if MQ.phase == "down" then pcall(inp.mouseUp); end;
			MQ.phase = "idle";
			local now = d();
			if now - (r.errAt or -1000) > 5 then
				r.errAt = now;
				notify(tostring(err), "Delve error");
			end;
		end;
	end;
r.lastRender = d();
r.conn = q.RenderStepped:Connect(function()
		r.lastRender = d();
		r.runStep();
	end);
-- RenderStepped stops firing when the window is minimized or throttled in the background;
-- in background mode Heartbeat keeps the farm running whenever rendering has stalled
r.conn2 = q.Heartbeat:Connect(function()
		if Q.background == true and d() - r.lastRender > .1 then
			r.runStep();
		end;
	end);

r.connectAntiAfk();
if Q.autoStats ~= false then
	fQ(true);
end;
notify("Settings opened. Use Right Shift or Open Delve to reopen them.", "Delve Potassium");
end;

local ok, err = xpcall(start, function(message)
	return debug.traceback(tostring(message), 2);
end);
if not ok then
	local env = type(getgenv) == "function" and getgenv();
	local state = env and env.Delve;
	if state and state.stop then pcall(state.stop); end;
	notify(err, "Delve startup error");
end;