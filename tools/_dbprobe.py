import sqlite3, shutil, os, sys
sys.stdout.reconfigure(encoding="utf-8")

dbs = [
    r"C:\Users\altai\AppData\Roaming\QoderCN\User\globalStorage\state.vscdb",
    r"C:\Users\altai\AppData\Roaming\QoderCN\User\workspaceStorage\a1de083e0444031b2f177f4eca797dc9\state.vscdb",
]

for db in dbs:
    print("\n" + "=" * 60)
    print(db)
    print("=" * 60)
    if not os.path.exists(db):
        print("  NOT FOUND")
        continue
    tmp = db + ".probe.tmp"
    try:
        shutil.copy2(db, tmp)
        con = sqlite3.connect(tmp)
        cur = con.cursor()
        tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        print("  tables: " + str(tables))
        rows = cur.execute(
            "SELECT key, length(value) FROM ItemTable "
            "WHERE lower(key) LIKE '%mcp%' OR lower(key) LIKE '%browser%' "
            "OR lower(key) LIKE '%aicoding%' OR lower(key) LIKE '%server%' "
            "OR lower(key) LIKE '%qwen%'"
        ).fetchall()
        print("  candidate keys (%d):" % len(rows))
        for k, vl in rows:
            print("    %s  (value len=%s)" % (k, vl))
        con.close()
    except Exception as e:
        print("  ERROR: " + str(e))
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass
