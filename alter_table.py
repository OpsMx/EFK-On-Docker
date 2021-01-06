import json
import datetime
import psycopg2



###MAIN###
####Connect to Database ######
conn = psycopg2.connect(database = "opsmx", user = "postgres", password = "networks123", host = "oes-db", port = "5432")
print ("Opened database successfully")
cur = conn.cursor()
cur.execute("""  ALTER TABLE loganalysis ALTER COLUMN v1identifiers TYPE varchar(1000);  """)
cur.execute("""  ALTER TABLE loganalysis ALTER COLUMN v2identifiers TYPE varchar(1000);  """)
conn.commit()

print("Operation Completed")
if conn is not None:
    conn.close()
    print("Closed DB connection conn")
