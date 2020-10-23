from pyspark import SparkContext
from pyspark.sql import SparkSession
from pyspark.sql.functions import *

region = 'us-east-2'
bucket = 'covid19-lake'
key = 'static-datasets/csv/state-abv/states_abv.csv'

sc = SparkContext()
sc._jsc.hadoopConfiguration().set('fs.s3a.endpoint', f's3-{region}.amazonaws.com')
spark = SparkSession(sc)

s3file = f's3a://{bucket}/{key}'
text = spark.read.text(s3file)
counts = text.select(explode(split(text.value, '\s+')).alias('word')).groupBy('word').count()
output = counts.collect()
for row in output[:10]:
    print(row)

spark.stop()
