import json
import datetime
import psycopg2



###MAIN###
####Connect to Database ######
conn = psycopg2.connect(database = "opsmx", user = "postgres", password = "networks123", host = "oes-db", port = "5432")
print ("Opened database successfully")
cur = conn.cursor()
cur.execute("""  ALTER TABLE logcluster ALTER COLUMN logdatasummary TYPE varchar(10485550);  """)
cur.execute("""  ALTER TABLE logcluster ALTER COLUMN clustertemplate TYPE varchar(10485750); """)
cur.execute("""  ALTER TABLE logcluster ALTER COLUMN timestamp TYPE varchar(500000); """)

cur.execute("""  ALTER TABLE loganalysis ALTER COLUMN failurecausecomment TYPE varchar(20000); """)
cur.execute("""  ALTER TABLE loganalysis ALTER COLUMN v1identifiers TYPE varchar(20001);  """)
cur.execute("""  ALTER TABLE loganalysis ALTER COLUMN v2identifiers TYPE varchar(20002);  """) 

cur.execute("""  ALTER TABLE logclusterdetails ALTER COLUMN cluster_data TYPE varchar(10485760);  """)
cur.execute("""  ALTER TABLE logclusterdetails ALTER COLUMN timestamp TYPE varchar(10485750);  """)

conn.commit()

print("Operation Completed")
if conn is not None:
    conn.close()
    print("Closed DB connection conn")
