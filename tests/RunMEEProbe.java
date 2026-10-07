import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.KahluaNumberConverter;
import zombie.Lua.LuaManager;
import zombie.scripting.objects.MoodleType;
import zombie.scripting.objects.Registries;
import zombie.ui.MoodlesUI;

public final class RunMEEProbe {
    private static int lateCounter;
    private static String sourceTree = "patched";
    @SuppressWarnings("unchecked")
    private static List<MoodleType> registryValues() throws Exception {
        var field = zombie.scripting.objects.Registry.class.getDeclaredField("values");
        field.setAccessible(true);
        return (List<MoodleType>) field.get(Registries.MOODLE_TYPE);
    }

    public static void appendRegistryMoodle(MoodleType type) throws Exception {
        registryValues().add(type);
    }

    // Reflection is used ONLY by this external test oracle, never by the mod.
    public static ArrayList<MoodleType> nativeOrderFor(MoodlesUI ui) throws Exception {
        var field = MoodlesUI.class.getDeclaredField("moodleUiState");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        var state = (Map<MoodleType, ?>) field.get(ui);
        return new ArrayList<>(state.keySet());
    }

    public static MoodlesUI newNativeUI() {
        var ui = new MoodlesUI();
        ui.setX(1910.0);
        ui.setY(120.0);
        ui.setWidth(32.0);
        ui.setVisible(true);
        return ui;
    }

    public static int hoverSlotFor(MoodlesUI ui) throws Exception {
        var field = MoodlesUI.class.getDeclaredField("mouseOverSlot");
        field.setAccessible(true);
        return field.getInt(ui);
    }

    private static void run(Path root, String variant, String id,
                            List<MoodleType> values, String layout) throws Exception {
        registryValues().clear();
        registryValues().addAll(values);
        var platform = J2SEPlatform.getInstance();
        KahluaTable env = platform.newEnvironment();
        var thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.env = env;
        LuaManager.thread = thread;
        zombie.ui.UIManager.defaultthread = thread;
        var converters = new KahluaConverterManager();
        KahluaNumberConverter.install(converters);
        var exposer = new LuaManager.Exposer(converters, platform, env);
        LuaManager.exposer = exposer;
        var classes = new Class<?>[]{HashMap.class, ArrayList.class,
                Registries.class, zombie.scripting.objects.Registry.class,
                MoodleType.class, MoodlesUI.class, java.util.List.class,
                java.util.Iterator.class};
        for (var cls : classes) exposer.setExposed(cls);
        for (var cls : classes) {
            exposer.exposeLikeJavaRecursively(cls, env);
        }
        for (var method : RunMEEProbe.class.getDeclaredMethods()) {
            if (java.lang.reflect.Modifier.isPublic(method.getModifiers())
                    && !method.getName().equals("main")) {
                exposer.exposeGlobalClassFunction(env, RunMEEProbe.class, method, method.getName());
            }
        }
        var ui = newNativeUI();
        env.rawset("probeUI", ui);
        env.rawset("probeNativeOrder", nativeOrderFor(ui));
        env.rawset("probeHiResID", id);
        var constructor = MoodleType.class.getDeclaredConstructor(String.class);
        constructor.setAccessible(true);
        var late = constructor.newInstance("MEEProbeLate");
        Registries.MOODLE_TYPE.register(new zombie.scripting.objects.ResourceLocation(
                "meeprobe", "late" + lateCounter++), late);
        registryValues().remove(late);
        env.rawset("probeLateType", late);
        for (var path : new Path[]{root.resolve("tests/bootstrap.lua"),
                root.resolve("Contents/mods/MoodleEffectsExplainedUnified/common/media/lua/client/MEE_ModOptions.lua"),
                root.resolve("Contents/mods/MoodleEffectsExplainedUnified/common/media/lua/client/MEE_MoodlesLuaFallback.lua"),
                root.resolve("Contents/mods/MoodleEffectsExplainedUnified/common/media/lua/client/MEE_MoodlesInLuaCompat.lua"),
                root.resolve("tests/cases.lua")}) {
            Object[] result = thread.pcall(LuaCompiler.loadstring(Files.readString(path), path.toString(), env), new Object[0]);
            if (!Boolean.TRUE.equals(result[0])) {
                throw new AssertionError(path + ": " + java.util.Arrays.toString(result));
            }
        }
        System.out.println("PASS " + variant + " + " + id + " / " + layout
                + ": " + env.rawget("probeChecks") + " assertions; "
                + values.size() + " real Java MoodleType keys; native order verified.");
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 1) sourceTree = args[1];
        zombie.core.random.RandStandard.INSTANCE.init();
        // This flag prevents texture/GPU initialization in this test JVM only.
        // No game client, dedicated server, or network service is launched.
        zombie.network.GameServer.server = true;
        zombie.core.Core.debug = false;
        System.out.println("Installed game: " + zombie.core.Core.getInstance().getGameVersion());
        MoodleType.FOOD_EATEN.toString();
        var original = new ArrayList<>(Registries.MOODLE_TYPE.values());
        var expanded = new ArrayList<>(original);
        var constructor = MoodleType.class.getDeclaredConstructor(String.class);
        constructor.setAccessible(true);
        for (int i = 0; i < 96; i++) {
            var type = constructor.newInstance("MEEProbe" + i);
            Registries.MOODLE_TYPE.register(new zombie.scripting.objects.ResourceLocation(
                    "meeprobe", "custom" + i), type);
            expanded.add(type);
        }
        Collections.shuffle(expanded, new java.util.Random(42021));
        Path root = Path.of(args[0]).toAbsolutePath();
        try {
            for (String variant : new String[]{"MoodleEffectsExplainedUnified"}) {
                for (String id : new String[]{"(no Hi-Res)", "Hi-Res-Clock", "Hi-Res-Clock_WIP"}) {
                    run(root, variant, id, original, "base registry");
                    run(root, variant, id, expanded, "shuffled extended registry");
                }
            }
        } finally {
            registryValues().clear();
            registryValues().addAll(original);
        }
        System.out.println("ALL PASS: actual PZ Kahlua, HashMap and MoodlesUI; Core.debug=false.");
    }
}
