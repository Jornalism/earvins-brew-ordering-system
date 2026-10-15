import {notFound} from 'next/navigation';
import {products} from '@/lib/menu';
import {ProductForm} from '@/components/product-form';
export default async function ProductPage({params}:{params:Promise<{id:string}>}){const {id}=await params;const product=products.find(x=>x.id===id);if(!product)notFound();return <ProductForm product={product}/>}
