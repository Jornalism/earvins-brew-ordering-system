import {CatalogProduct} from '@/components/catalog-product';
export default async function ProductPage({params}:{params:Promise<{id:string}>}){const {id}=await params;return <CatalogProduct id={id}/>}
